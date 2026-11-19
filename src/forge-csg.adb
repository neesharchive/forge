package body Forge.CSG with SPARK_Mode => Off is
   --  Off: index-chasing through the workspace. No heap, no recursion.

   use Exact;
   use type Validity.Edge_Count;

   Out_Of_Room : exception;      --  workspace full; Apply reports Workspace_Full
   Result_Too_Big : exception;   --  Result full; Apply reports Result_Full

   Plane_Steps : constant := 64;
   --  On a plane: |N . (P - A)| <= Plane_Steps * L1 (N), about 64 steps.
   --  Covers cut points rounded to the grid, a few cuts in a row.

   Weld_Steps : constant := 1024;
   --  Points this close on every axis are one vertex. Above Plane_Steps.

   Key_Reach : constant := 15 * Weld_Steps;
   --  Points within Weld_Steps have keys (3x + 5y + 7z) within this.

   type Placement is (Coplanar_Same, Coplanar_Opposite, In_Front, In_Back, Spanning);

   function Key (P : Point) return Big is (3 * Big (P.X) + 5 * Big (P.Y) + 7 * Big (P.Z));

   function Near (A, B : Point) return Boolean is
     (abs (Big (A.X) - Big (B.X)) <= Weld_Steps and then abs (Big (A.Y) - Big (B.Y)) <= Weld_Steps
      and then abs (Big (A.Z) - Big (B.Z)) <= Weld_Steps);

   --  Two normals of one plane face the same way: same sign on the largest.
   function Same_Facing (N, M : Vector) return Boolean is
     (if abs N.X >= abs N.Y and then abs N.X >= abs N.Z then (N.X > 0) = (M.X > 0)
      elsif abs N.Y >= abs N.Z then (N.Y > 0) = (M.Y > 0)
      else (N.Z > 0) = (M.Z > 0));

   --  B lies on the line through A and C, to within Weld_Steps.
   function On_Line (A, B, C : Point) return Boolean is
     (Max_Abs (Cross (C - A, B - A)) <= Weld_Steps * Max_Abs (C - A));

   procedure New_Polygon (W : in out Workspace; Room : Count; P : out Count);
   procedure Put (W : in out Workspace; P : Count; V : Point);
   procedure Push (W : in out Workspace; List : in out Count; P : Count);
   procedure Move_All (W : in out Workspace; From : Count; Into : in out Count);
   procedure Flip (W : in out Workspace; P : Count);
   procedure New_Node (W : in out Workspace; Tree : Tree_Id; X : out Count);
   procedure Push_Job (W : in out Workspace; Top : in out Count; At_Node, List : Count);
   procedure Split
     (W           : in out Workspace;
      N           : Vector;
      A           : Point;
      P           : Count;
      Where       : out Placement;
      Front_Piece : out Count;
      Back_Piece  : out Count);
   procedure Build (W : in out Workspace; Root, List : Count);
   procedure Clip_List (W : in out Workspace; Root, List : Count; Kept : out Count);
   function Clear_Of (W : Workspace; P : Count; Lo, Hi : Point) return Boolean;
   procedure Clip_Tree (W : in out Workspace; Tree, By : Tree_Number);
   procedure Invert (W : in out Workspace; Tree : Tree_Number);
   procedure Take_All (W : in out Workspace; Tree : Tree_Number; List : out Count);
   procedure Face_Planes (W : in out Workspace; M : Tri_Mesh);
   procedure Load (W : in out Workspace; M : Tri_Mesh; Tree : Tree_Number);
   procedure Sort_By (Perm : in out Count_Array; N : Count; By : Key_Array);
   procedure Find (Parent : in out Count_Array; X : Count; Root : out Count);
   procedure Clean (L : in out Count_Array; Start : Count; Len : in out Count);
   procedure Emit (W : in out Workspace; List : Count; Result : in out Tri_Mesh);
   procedure Append_Mesh (Result : in out Tri_Mesh; M : Tri_Mesh);
   procedure Say (Reason : out Reason_String; Last : out Natural; Msg : String);

   ---------------------------------------------------------------------
   --  Polygons
   ---------------------------------------------------------------------

   procedure New_Polygon (W : in out Workspace; Room : Count; P : out Count) is
   begin
      if W.Polys_N >= W.Max_Polygons or else Room > W.Max_Points - W.Pool_N then
         raise Out_Of_Room;
      end if;
      W.Polys_N := W.Polys_N + 1;
      P := W.Polys_N;
      W.Polys (P) := (N => (0, 0, 0), A => (0, 0, 0), First => W.Pool_N + 1, Size => 0,
                      Next => 0);
      W.Pool_N := W.Pool_N + Room;
   end New_Polygon;

   procedure Put (W : in out Workspace; P : Count; V : Point) is
   begin
      W.Pool (W.Polys (P).First + W.Polys (P).Size) := V;
      W.Polys (P).Size := W.Polys (P).Size + 1;
   end Put;

   procedure Push (W : in out Workspace; List : in out Count; P : Count) is
   begin
      W.Polys (P).Next := List;
      List := P;
   end Push;

   procedure Move_All (W : in out Workspace; From : Count; Into : in out Count) is
      P    : Count := From;
      Next : Count;
   begin
      while P /= 0 loop
         Next := W.Polys (P).Next;
         Push (W, Into, P);
         P := Next;
      end loop;
   end Move_All;

   --  Turn a polygon over: reverse its points, negate its normal.
   procedure Flip (W : in out Workspace; P : Count) is
      First : constant Count := W.Polys (P).First;
      Last  : constant Count := First + W.Polys (P).Size - 1;
      T     : Point;
   begin
      for I in 0 .. (Last - First + 1) / 2 - 1 loop
         T := W.Pool (First + I);
         W.Pool (First + I) := W.Pool (Last - I);
         W.Pool (Last - I) := T;
      end loop;
      W.Polys (P).N := (-W.Polys (P).N.X, -W.Polys (P).N.Y, -W.Polys (P).N.Z);
   end Flip;

   procedure New_Node (W : in out Workspace; Tree : Tree_Id; X : out Count) is
   begin
      if W.Nodes_N >= W.Max_Nodes then
         raise Out_Of_Room;
      end if;
      W.Nodes_N := W.Nodes_N + 1;
      X := W.Nodes_N;
      W.Nodes (X) := (Tree => Tree, others => <>);
   end New_Node;

   --  Explicit stack for tree walks. Each node gets at most one job per
   --  walk, so Max_Nodes jobs are enough.
   procedure Push_Job (W : in out Workspace; Top : in out Count; At_Node, List : Count) is
   begin
      if Top >= W.Max_Nodes then
         raise Out_Of_Room;
      end if;
      Top := Top + 1;
      W.Jobs (Top) := (At_Node => At_Node, List => List);
   end Push_Job;

   --  Classify polygon P against the plane (N, A). Across it, P is cut in
   --  two; a piece with fewer than three points is dropped (0).
   procedure Split
     (W           : in out Workspace;
      N           : Vector;
      A           : Point;
      P           : Count;
      Where       : out Placement;
      Front_Piece : out Count;
      Back_Piece  : out Count)
   is
      First      : constant Count := W.Polys (P).First;
      Size       : constant Count := W.Polys (P).Size;
      Tol        : constant Big := Plane_Steps * L1 (N);
      Above_Seen : Boolean := False;
      Below_Seen : Boolean := False;

      function Point_At (I : Count) return Point is (W.Pool (First + I mod Size));
      function S (I : Count) return Integer is (Side (N, A, Point_At (I), Tol));
      function Crosses (I : Count) return Boolean is (S (I) * S (I + 1) < 0);

   begin
      Front_Piece := 0;
      Back_Piece := 0;
      for I in 0 .. Size - 1 loop
         case S (I) is
            when 1      => Above_Seen := True;
            when -1     => Below_Seen := True;
            when others => null;
         end case;
      end loop;

      if not Above_Seen and then not Below_Seen then
         Where := (if Same_Facing (N, W.Polys (P).N) then Coplanar_Same else Coplanar_Opposite);
      elsif not Below_Seen then
         Where := In_Front;
      elsif not Above_Seen then
         Where := In_Back;
      else
         Where := Spanning;
         declare
            Front_Room, Back_Room : Count := 0;
         begin
            for I in 0 .. Size - 1 loop
               if S (I) /= -1 then
                  Front_Room := Front_Room + 1;
               end if;
               if S (I) /= 1 then
                  Back_Room := Back_Room + 1;
               end if;
               if Crosses (I) then
                  Front_Room := Front_Room + 1;
                  Back_Room := Back_Room + 1;
               end if;
            end loop;
            New_Polygon (W, Front_Room, Front_Piece);
            New_Polygon (W, Back_Room, Back_Piece);
         end;
         W.Polys (Front_Piece).N := W.Polys (P).N;
         W.Polys (Front_Piece).A := W.Polys (P).A;
         W.Polys (Back_Piece).N := W.Polys (P).N;
         W.Polys (Back_Piece).A := W.Polys (P).A;
         for I in 0 .. Size - 1 loop
            if S (I) /= -1 then
               Put (W, Front_Piece, Point_At (I));
            end if;
            if S (I) /= 1 then
               Put (W, Back_Piece, Point_At (I));
            end if;
            if Crosses (I) then
               declare
                  X : constant Point := Crossing (N, A, Point_At (I), Point_At (I + 1));
               begin
                  Put (W, Front_Piece, X);
                  Put (W, Back_Piece, X);
               end;
            end if;
         end loop;
         if W.Polys (Front_Piece).Size < 3 then
            Front_Piece := 0;
         end if;
         if W.Polys (Back_Piece).Size < 3 then
            Back_Piece := 0;
         end if;
      end if;
   end Split;

   ---------------------------------------------------------------------
   --  BSP trees (csg.js: Node.build, clipPolygons, clipTo, invert)
   ---------------------------------------------------------------------

   --  Insert List under Root. A node takes the plane of the first polygon
   --  to reach it; polygons in that plane stay there.
   procedure Build (W : in out Workspace; Root, List : Count) is
      Top : Count := 0;
   begin
      if List /= 0 then
         Push_Job (W, Top, Root, List);
      end if;
      while Top > 0 loop
         declare
            J     : constant Job := W.Jobs (Top);
            X     : constant Count := J.At_Node;
            P     : Count := J.List;
            Next  : Count;
            Here  : Count := W.Nodes (X).Head;
            Front : Count := 0;
            Back  : Count := 0;
            Where : Placement;
            FP    : Count;
            BP    : Count;
         begin
            Top := Top - 1;
            if not W.Nodes (X).Has_Plane then
               W.Nodes (X).Has_Plane := True;
               W.Nodes (X).N := W.Polys (P).N;
               W.Nodes (X).A := W.Polys (P).A;
            end if;
            declare
               NX : constant Vector := W.Nodes (X).N;
               AX : constant Point := W.Nodes (X).A;
            begin
               while P /= 0 loop
                  Next := W.Polys (P).Next;
                  Split (W, NX, AX, P, Where, FP, BP);
                  case Where is
                     when Coplanar_Same | Coplanar_Opposite => Push (W, Here, P);
                     when In_Front => Push (W, Front, P);
                     when In_Back  => Push (W, Back, P);
                     when Spanning =>
                        if FP /= 0 then
                           Push (W, Front, FP);
                        end if;
                        if BP /= 0 then
                           Push (W, Back, BP);
                        end if;
                  end case;
                  P := Next;
               end loop;
            end;
            W.Nodes (X).Head := Here;
            if Front /= 0 then
               if W.Nodes (X).Front = 0 then
                  declare
                     Child : Count;
                  begin
                     New_Node (W, W.Nodes (X).Tree, Child);
                     W.Nodes (X).Front := Child;
                  end;
               end if;
               Push_Job (W, Top, W.Nodes (X).Front, Front);
            end if;
            if Back /= 0 then
               if W.Nodes (X).Back = 0 then
                  declare
                     Child : Count;
                  begin
                     New_Node (W, W.Nodes (X).Tree, Child);
                     W.Nodes (X).Back := Child;
                  end;
               end if;
               Push_Job (W, Top, W.Nodes (X).Back, Back);
            end if;
         end;
      end loop;
   end Build;

   --  Keep the parts of List outside the solid under Root.
   procedure Clip_List (W : in out Workspace; Root, List : Count; Kept : out Count) is
      Top : Count := 0;
   begin
      Kept := 0;
      if List /= 0 then
         Push_Job (W, Top, Root, List);
      end if;
      while Top > 0 loop
         declare
            J     : constant Job := W.Jobs (Top);
            X     : constant Count := J.At_Node;
            P     : Count := J.List;
            Next  : Count;
            Front : Count := 0;
            Back  : Count := 0;
            Where : Placement;
            FP    : Count;
            BP    : Count;
         begin
            Top := Top - 1;
            if not W.Nodes (X).Has_Plane then
               Move_All (W, P, Kept);
            else
               declare
                  NX : constant Vector := W.Nodes (X).N;
                  AX : constant Point := W.Nodes (X).A;
               begin
                  while P /= 0 loop
                     Next := W.Polys (P).Next;
                     Split (W, NX, AX, P, Where, FP, BP);
                     case Where is
                        when Coplanar_Same | In_Front => Push (W, Front, P);
                        when Coplanar_Opposite | In_Back => Push (W, Back, P);
                        when Spanning =>
                           if FP /= 0 then
                              Push (W, Front, FP);
                           end if;
                           if BP /= 0 then
                              Push (W, Back, BP);
                           end if;
                     end case;
                     P := Next;
                  end loop;
               end;
               if Front /= 0 then
                  if W.Nodes (X).Front /= 0 then
                     Push_Job (W, Top, W.Nodes (X).Front, Front);
                  else
                     Move_All (W, Front, Kept);
                  end if;
               end if;
               if Back /= 0 and then W.Nodes (X).Back /= 0 then
                  Push_Job (W, Top, W.Nodes (X).Back, Back);
               end if;
            end if;
         end;
      end loop;
   end Clip_List;

   --  P is outside the box Lo .. Hi by more than Weld_Steps.
   function Clear_Of (W : Workspace; P : Count; Lo, Hi : Point) return Boolean is
      First : constant Count := W.Polys (P).First;
      PLo   : Point := W.Pool (First);
      PHi   : Point := W.Pool (First);
   begin
      for I in First + 1 .. First + W.Polys (P).Size - 1 loop
         PLo := (Coord'Min (PLo.X, W.Pool (I).X), Coord'Min (PLo.Y, W.Pool (I).Y),
                 Coord'Min (PLo.Z, W.Pool (I).Z));
         PHi := (Coord'Max (PHi.X, W.Pool (I).X), Coord'Max (PHi.Y, W.Pool (I).Y),
                 Coord'Max (PHi.Z, W.Pool (I).Z));
      end loop;
      return Big (PHi.X) < Big (Lo.X) - Weld_Steps or else Big (PLo.X) > Big (Hi.X) + Weld_Steps
        or else Big (PHi.Y) < Big (Lo.Y) - Weld_Steps or else Big (PLo.Y) > Big (Hi.Y) + Weld_Steps
        or else Big (PHi.Z) < Big (Lo.Z) - Weld_Steps or else Big (PLo.Z) > Big (Hi.Z) + Weld_Steps;
   end Clear_Of;

   --  Clip Tree's polygons by the solid of By. A polygon clear of By's box
   --  is not cut by By's endless planes: kept whole, or dropped whole when
   --  By is inside out.
   procedure Clip_Tree (W : in out Workspace; Tree, By : Tree_Number) is
      Far  : Count;
      Near_List : Count;
      Kept : Count;
      P    : Count;
      Next : Count;
   begin
      for X in 1 .. W.Nodes_N loop
         if W.Nodes (X).Tree = Tree then
            Far := 0;
            Near_List := 0;
            P := W.Nodes (X).Head;
            while P /= 0 loop
               Next := W.Polys (P).Next;
               if not Clear_Of (W, P, W.Lo (By), W.Hi (By)) then
                  Push (W, Near_List, P);
               elsif not W.Inverted (By) then
                  Push (W, Far, P);
               end if;
               P := Next;
            end loop;
            Clip_List (W, W.Roots (By), Near_List, Kept);
            Move_All (W, Far, Kept);
            W.Nodes (X).Head := Kept;
         end if;
      end loop;
   end Clip_Tree;

   --  Turn a solid inside out.
   procedure Invert (W : in out Workspace; Tree : Tree_Number) is
      P : Count;
      F : Count;
   begin
      W.Inverted (Tree) := not W.Inverted (Tree);
      for X in 1 .. W.Nodes_N loop
         if W.Nodes (X).Tree = Tree then
            P := W.Nodes (X).Head;
            while P /= 0 loop
               Flip (W, P);
               P := W.Polys (P).Next;
            end loop;
            W.Nodes (X).N := (-W.Nodes (X).N.X, -W.Nodes (X).N.Y, -W.Nodes (X).N.Z);
            F := W.Nodes (X).Front;
            W.Nodes (X).Front := W.Nodes (X).Back;
            W.Nodes (X).Back := F;
         end if;
      end loop;
   end Invert;

   procedure Take_All (W : in out Workspace; Tree : Tree_Number; List : out Count) is
   begin
      List := 0;
      for X in 1 .. W.Nodes_N loop
         if W.Nodes (X).Tree = Tree then
            Move_All (W, W.Nodes (X).Head, List);
            W.Nodes (X).Head := 0;
         end if;
      end loop;
   end Take_All;

   --  W.Loop_1 (T): the triangle whose plane triangle T of M uses. A needle
   --  left by an earlier boolean has corners almost in a line, so its own
   --  plane is nearly arbitrary; it takes instead the plane of the largest
   --  triangle reachable across edges that holds all its corners. Needs
   --  W.Pos (1 .. NV); borrows the repair arrays, free until Emit.
   procedure Face_Planes (W : in out Workspace; M : Tri_Mesh) is
      NV      : constant Count := Count (M.NV);
      NT      : constant Count := Count (M.NT);
      Changed : Boolean := True;
      Passes  : Natural := 0;

      function Vid (T : Count; K : Natural) return Count is
        (Count (case K is
                   when 0      => M.T (Triangle_Index (T)).A,
                   when 1      => M.T (Triangle_Index (T)).B,
                   when others => M.T (Triangle_Index (T)).C));
      function Normal (T : Count) return Vector is
        (Cross (W.Pos (Vid (T, 1)) - W.Pos (Vid (T, 0)), W.Pos (Vid (T, 2)) - W.Pos (Vid (T, 0))));
      function Has (T, V : Count) return Boolean is
        (Vid (T, 0) = V or else Vid (T, 1) = V or else Vid (T, 2) = V);
      function Holds (F, T : Count) return Boolean;

      function Holds (F, T : Count) return Boolean is
         N   : constant Vector := Normal (F);
         A   : constant Point := W.Pos (Vid (F, 0));
         Tol : constant Big := Plane_Steps * L1 (N);
      begin
         return (for all K in 0 .. 2 => Side (N, A, W.Pos (Vid (T, K)), Tol) = 0);
      end Holds;

   begin
      --  Triangles around vertex V: Occ (Parent (V) .. Parent (V + 1) - 1).
      for V in 1 .. NV loop
         W.Root_Id (V) := 0;
      end loop;
      for T in 1 .. NT loop
         for K in 0 .. 2 loop
            W.Root_Id (Vid (T, K)) := W.Root_Id (Vid (T, K)) + 1;
         end loop;
         W.Loop_1 (T) := T;
         W.Key (T) := Max_Abs (Normal (T));
      end loop;
      W.Parent (1) := 1;
      for V in 1 .. NV loop
         W.Parent (V + 1) := W.Parent (V) + W.Root_Id (V);
         W.Perm (V) := W.Parent (V);
      end loop;
      for T in 1 .. NT loop
         for K in 0 .. 2 loop
            W.Occ (W.Perm (Vid (T, K))) := T;
            W.Perm (Vid (T, K)) := W.Perm (Vid (T, K)) + 1;
         end loop;
      end loop;

      while Changed and then Passes < 64 loop
         Changed := False;
         Passes := Passes + 1;
         for T in 1 .. NT loop
            declare
               Best : Count := W.Loop_1 (T);
            begin
               for K in 0 .. 2 loop
                  declare
                     V : constant Count := Vid (T, K);
                     U : constant Count := Vid (T, (K + 1) mod 3);
                  begin
                     for S in W.Parent (V) .. W.Parent (V + 1) - 1 loop
                        declare
                           J : constant Count := W.Occ (S);   --  across edge V-U
                           F : constant Count := W.Loop_1 (J);
                        begin
                           if J /= T and then Has (J, U) and then W.Key (F) > W.Key (Best)
                             and then Holds (F, T)
                           then
                              Best := F;
                           end if;
                        end;
                     end loop;
                  end;
               end loop;
               if Best /= W.Loop_1 (T) then
                  W.Loop_1 (T) := Best;
                  Changed := True;
               end if;
            end;
         end loop;
      end loop;
   end Face_Planes;

   --  A tree of M's triangles (zero-area ones skipped). They go in shuffled:
   --  a cylinder's walls in order would each shave a sliver off a crossing
   --  polygon. The seed is fixed, so replay stays exact.
   procedure Load (W : in out Workspace; M : Tri_Mesh; Tree : Tree_Number) is
      type Random is mod 2 ** 64;
      Seed    : Random := 16#9E37_79B9_7F4A_7C15#;
      First_P : constant Count := W.Polys_N + 1;
      List    : Count := 0;
      P       : Count;
      J       : Count;
      T       : Count;
   begin
      New_Node (W, Tree, W.Roots (Tree));
      W.Inverted (Tree) := False;
      W.Lo (Tree) := To_Point (M.V (1));
      W.Hi (Tree) := W.Lo (Tree);
      for I in 2 .. M.NV loop
         declare
            V : constant Point := To_Point (M.V (I));
         begin
            W.Lo (Tree) := (Coord'Min (W.Lo (Tree).X, V.X), Coord'Min (W.Lo (Tree).Y, V.Y),
                            Coord'Min (W.Lo (Tree).Z, V.Z));
            W.Hi (Tree) := (Coord'Max (W.Hi (Tree).X, V.X), Coord'Max (W.Hi (Tree).Y, V.Y),
                            Coord'Max (W.Hi (Tree).Z, V.Z));
         end;
      end loop;
      if Count (M.NV) + 1 > W.Max_Points or else 3 * Count (M.NT) > W.Max_Points then
         raise Out_Of_Room;
      end if;
      for I in 1 .. M.NV loop
         W.Pos (Count (I)) := To_Point (M.V (I));
      end loop;
      Face_Planes (W, M);
      for I in 1 .. M.NT loop
         declare
            A : constant Point := W.Pos (Count (M.T (I).A));
            B : constant Point := W.Pos (Count (M.T (I).B));
            C : constant Point := W.Pos (Count (M.T (I).C));
            F : constant Triangle_Index := Triangle_Index (W.Loop_1 (Count (I)));
            FA : constant Point := W.Pos (Count (M.T (F).A));
         begin
            if not Is_Zero (Cross (B - A, C - A)) then
               New_Polygon (W, 3, P);
               Put (W, P, A);
               Put (W, P, B);
               Put (W, P, C);
               W.Polys (P).N := Cross (W.Pos (Count (M.T (F).B)) - FA,
                                       W.Pos (Count (M.T (F).C)) - FA);
               W.Polys (P).A := FA;
            end if;
         end;
      end loop;
      --  Fisher-Yates, Perm as scratch.
      for I in 1 .. W.Polys_N - First_P + 1 loop
         W.Perm (I) := First_P + I - 1;
      end loop;
      for I in reverse 2 .. W.Polys_N - First_P + 1 loop
         Seed := Seed * 6_364_136_223_846_793_005 + 1_442_695_040_888_963_407;
         J := 1 + Count ((Seed / 2 ** 33) mod Random (I));
         T := W.Perm (I);
         W.Perm (I) := W.Perm (J);
         W.Perm (J) := T;
      end loop;
      for I in 1 .. W.Polys_N - First_P + 1 loop
         Push (W, List, W.Perm (I));
      end loop;
      Build (W, W.Roots (Tree), List);
   end Load;

   ---------------------------------------------------------------------
   --  Repair: polygon soup to an indexed, closed triangle mesh
   ---------------------------------------------------------------------

   --  Heap sort of Perm (1 .. N) so that By (Perm (I)) increases.
   procedure Sort_By (Perm : in out Count_Array; N : Count; By : Key_Array) is
      T : Count;
      procedure Sift (Start, Stop : Count);
      procedure Sift (Start, Stop : Count) is
         Root  : Count := Start;
         Child : Count;
         Tmp   : Count;
      begin
         while Root <= Stop / 2 loop
            Child := 2 * Root;
            if Child < Stop and then By (Perm (Child)) < By (Perm (Child + 1)) then
               Child := Child + 1;
            end if;
            exit when By (Perm (Root)) >= By (Perm (Child));
            Tmp := Perm (Root);
            Perm (Root) := Perm (Child);
            Perm (Child) := Tmp;
            Root := Child;
         end loop;
      end Sift;
   begin
      for Start in reverse 1 .. N / 2 loop
         Sift (Start, N);
      end loop;
      for Stop in reverse 2 .. N loop
         T := Perm (1);
         Perm (1) := Perm (Stop);
         Perm (Stop) := T;
         Sift (1, Stop - 1);
      end loop;
   end Sort_By;

   procedure Find (Parent : in out Count_Array; X : Count; Root : out Count) is
      Y : Count := X;
   begin
      while Parent (Y) /= Y loop
         Parent (Y) := Parent (Parent (Y));  --  path halving
         Y := Parent (Y);
      end loop;
      Root := Y;
   end Find;

   --  Tidy the cyclic loop L (Start .. Start + Len - 1): drop x, x and fold
   --  spikes x, y, x. Fewer than three vertices left: Len = 0.
   procedure Clean (L : in out Count_Array; Start : Count; Len : in out Count) is
      Changed : Boolean := True;
      function At_Pos (I : Count) return Count is (L (Start + I mod Len));
      procedure Remove (I : Count);
      procedure Remove (I : Count) is
      begin
         for J in I .. Len - 2 loop
            L (Start + J) := L (Start + J + 1);
         end loop;
         Len := Len - 1;
      end Remove;
   begin
      while Changed and then Len >= 3 loop
         Changed := False;
         for I in 0 .. Len - 1 loop
            if At_Pos (I) = At_Pos (I + 1) then
               Remove ((I + 1) mod Len);
               Changed := True;
               exit;
            elsif At_Pos (I) = At_Pos (I + 2) then
               declare
                  A : constant Count := (I + 1) mod Len;
                  B : constant Count := (I + 2) mod Len;
               begin
                  Remove (Count'Max (A, B));
                  Remove (Count'Min (A, B));
               end;
               Changed := True;
               exit;
            end if;
         end loop;
      end loop;
      if Len < 3 then
         Len := 0;
      end if;
   end Clean;

   procedure Emit (W : in out Workspace; List : Count; Result : in out Tri_Mesh) is
      NP : Count := 0;   --  output polygons
      K  : Count := 0;   --  points of the output polygons
      NW : Count := 0;   --  welded vertices
      N2 : Count := 0;   --  used length of Loop_2
      P  : Count;
      R  : Count;
      Ok : Boolean;

      procedure Add_2 (X : Count; T : Big);
      function First_Key_At_Least (Low : Big) return Count;
      procedure Tri (A, B, C : Vertex_Index);
      procedure Fan (I : Count);
      procedure Fan_Outline (S, N : Count);

      procedure Add_2 (X : Count; T : Big) is
      begin
         if N2 >= W.Max_Points then
            raise Out_Of_Room;
         end if;
         N2 := N2 + 1;
         W.Loop_2 (N2) := X;
         W.Key (N2) := T;
      end Add_2;

      function First_Key_At_Least (Low : Big) return Count is
         Lo  : Count := 1;
         Hi  : Count := NW + 1;
         Mid : Count;
      begin
         while Lo < Hi loop
            Mid := Lo + (Hi - Lo) / 2;
            if W.Key_W (W.By_Key (Mid)) < Low then
               Lo := Mid + 1;
            else
               Hi := Mid;
            end if;
         end loop;
         return Lo;
      end First_Key_At_Least;

      procedure Tri (A, B, C : Vertex_Index) is
      begin
         Add_Triangle (Result, A, B, C, Ok);
         if not Ok then
            raise Result_Too_Big;
         end if;
      end Tri;

      --  Triangles for output polygon I. Welding can pinch an outline into
      --  a figure 8 (one vertex visited twice); one fan would fold its lobes
      --  over each other, so it is cut there into two outlines first. The
      --  pieces wait on W.Jobs, free once the BSP is done.
      procedure Fan (I : Count) is
         Top : Count := 1;
         S   : Count;
         N   : Count;
      begin
         W.Jobs (1) := (At_Node => W.Start_2 (I), List => W.Len_2 (I));
         while Top > 0 loop
            S := W.Jobs (Top).At_Node;
            N := W.Jobs (Top).List;
            Top := Top - 1;
            Clean (W.Loop_2, S, N);
            declare
               function Id (E : Count) return Count is (W.Loop_2 (S + E mod N));
               First, Second : Count := 0;   --  a repeated vertex at these places
            begin
               for E in 0 .. N - 2 loop
                  for F in E + 1 .. N - 1 loop
                     if First = Second and then Id (E) = Id (F) then
                        First := E;
                        Second := F;
                     end if;
                  end loop;
               end loop;
               if First /= Second then
                  --  Lobe one is in place; lobe two wraps, so it is copied.
                  declare
                     Copy : constant Count := N2 + 1;
                  begin
                     for E in Second .. N - 1 loop
                        Add_2 (Id (E), 0);
                     end loop;
                     for E in 0 .. First - 1 loop
                        Add_2 (Id (E), 0);
                     end loop;
                     if Top + 2 > W.Max_Nodes then
                        raise Out_Of_Room;
                     end if;
                     W.Jobs (Top + 1) := (At_Node => S + First, List => Second - First);
                     W.Jobs (Top + 2) := (At_Node => Copy, List => N - (Second - First));
                     Top := Top + 2;
                  end;
               elsif N >= 3 then
                  Fan_Outline (S, N);
               end if;
            end;
         end loop;
      end Fan;

      --  From a corner if strictly convex, else from the centre, so a point
      --  along an edge never makes a zero-area triangle.
      procedure Fan_Outline (S, N : Count) is
         Simple : Boolean := True;
         function Id (E : Count) return Vertex_Index is (W.Remap (W.Loop_2 (S + E mod N)));
         function At_Pos (E : Count) return Point is (W.Pos (W.Loop_2 (S + E mod N)));
      begin
         if N = 3 then
            Tri (Id (0), Id (1), Id (2));
            return;
         end if;
         for E in 0 .. N - 1 loop
            for F in E + 1 .. N - 1 loop
               if Id (E) = Id (F) then
                  Simple := False;   --  Fan splits these off; kept as a safety net
               end if;
            end loop;
            if On_Line (At_Pos (E + N - 1), At_Pos (E), At_Pos (E + 1)) then
               Simple := False;
            end if;
         end loop;
         if Simple then
            for E in 1 .. N - 2 loop
               Tri (Id (0), Id (E), Id (E + 1));
            end loop;
         else
            declare
               SX, SY, SZ : Big := 0;
               Centre     : Vertex_Index;
            begin
               for E in 0 .. N - 1 loop
                  SX := SX + Big (At_Pos (E).X);
                  SY := SY + Big (At_Pos (E).Y);
                  SZ := SZ + Big (At_Pos (E).Z);
               end loop;
               Add_Vertex (Result, To_Vec3 ((Coord (SX / Big (N)), Coord (SY / Big (N)),
                                             Coord (SZ / Big (N)))), Centre, Ok);
               if not Ok then
                  raise Result_Too_Big;
               end if;
               for E in 0 .. N - 1 loop
                  Tri (Centre, Id (E), Id (E + 1));
               end loop;
            end;
         end if;
      end Fan_Outline;

   begin
      --  1. The surviving polygons and their points.
      P := List;
      while P /= 0 loop
         NP := NP + 1;
         W.Out_P (NP) := P;
         W.Start_1 (NP) := K + 1;
         W.Len_1 (NP) := W.Polys (P).Size;
         for I in 0 .. W.Polys (P).Size - 1 loop
            K := K + 1;
            W.Occ (K) := W.Polys (P).First + I;
         end loop;
         P := W.Polys (P).Next;
      end loop;

      --  2. Weld. Sorted by key, each point is compared only with those
      --  less than Key_Reach before it.
      for I in 1 .. K loop
         W.Key (I) := Key (W.Pool (W.Occ (I)));
         W.Perm (I) := I;
         W.Parent (I) := I;
         W.Root_Id (I) := 0;
      end loop;
      Sort_By (W.Perm, K, W.Key);
      for I in 2 .. K loop
         declare
            PI : constant Count := W.Perm (I);
            J  : Count := I - 1;
            RA : Count;
            RB : Count;
         begin
            while J >= 1 and then W.Key (PI) - W.Key (W.Perm (J)) <= Key_Reach loop
               if Near (W.Pool (W.Occ (PI)), W.Pool (W.Occ (W.Perm (J)))) then
                  Find (W.Parent, PI, RA);
                  Find (W.Parent, W.Perm (J), RB);
                  if RA /= RB then
                     W.Parent (RA) := RB;
                  end if;
               end if;
               J := J - 1;
            end loop;
         end;
      end loop;
      for I in 1 .. K loop
         Find (W.Parent, W.Perm (I), R);
         if W.Root_Id (R) = 0 then
            NW := NW + 1;
            W.Root_Id (R) := NW;
            W.Pos (NW) := W.Pool (W.Occ (R));
         end if;
         W.Loop_1 (W.Perm (I)) := W.Root_Id (R);
      end loop;

      --  3. Each polygon is now a loop of welded vertices; tidy it.
      for I in 1 .. NP loop
         Clean (W.Loop_1, W.Start_1 (I), W.Len_1 (I));
      end loop;

      --  4. T-joints: vertices within Weld_Steps of edge U-V, between its
      --  ends, are inserted in order. Candidates have keys between U's and
      --  V's, found by binary search.
      for V in 1 .. NW loop
         W.By_Key (V) := V;
         W.Key_W (V) := Key (W.Pos (V));
      end loop;
      Sort_By (W.By_Key, NW, W.Key_W);
      for I in 1 .. NP loop
         W.Start_2 (I) := N2 + 1;
         W.Len_2 (I) := 0;
         if W.Len_1 (I) >= 3 then
            for E in 0 .. W.Len_1 (I) - 1 loop
               declare
                  U    : constant Count := W.Loop_1 (W.Start_1 (I) + E);
                  V    : constant Count := W.Loop_1 (W.Start_1 (I) + (E + 1) mod W.Len_1 (I));
                  PU   : constant Point := W.Pos (U);
                  UV   : constant Vector := W.Pos (V) - PU;
                  L2   : constant Big := Inner (UV, UV);
                  Reach : constant Big := Weld_Steps * Max_Abs (UV);
                  Low  : constant Big := Big'Min (W.Key_W (U), W.Key_W (V)) - Key_Reach;
                  High : constant Big := Big'Max (W.Key_W (U), W.Key_W (V)) + Key_Reach;
                  Seg  : constant Count := N2 + 2;   --  where this edge's insertions start
                  J    : Count;
               begin
                  Add_2 (U, 0);
                  J := First_Key_At_Least (Low);
                  while J <= NW and then W.Key_W (W.By_Key (J)) <= High loop
                     declare
                        X  : constant Count := W.By_Key (J);
                        UX : constant Vector := W.Pos (X) - PU;
                        T  : constant Big := Inner (UX, UV);   --  L2 times the parameter
                     begin
                        if X /= U and then X /= V and then T > 0 and then T < L2
                          and then Max_Abs (Cross (UV, UX)) <= Reach
                        then
                           Add_2 (X, T);
                        end if;
                     end;
                     J := J + 1;
                  end loop;
                  --  Insertion sort of this edge's new points along it.
                  for A in Seg + 1 .. N2 loop
                     declare
                        XA : constant Count := W.Loop_2 (A);
                        TA : constant Big := W.Key (A);
                        B  : Count := A;
                     begin
                        while B > Seg and then W.Key (B - 1) > TA loop
                           W.Loop_2 (B) := W.Loop_2 (B - 1);
                           W.Key (B) := W.Key (B - 1);
                           B := B - 1;
                        end loop;
                        W.Loop_2 (B) := XA;
                        W.Key (B) := TA;
                     end;
                  end loop;
               end;
            end loop;
            W.Len_2 (I) := N2 - W.Start_2 (I) + 1;
            Clean (W.Loop_2, W.Start_2 (I), W.Len_2 (I));
         end if;
      end loop;

      --  5. Vertices still in use, back to Scalar, then triangles.
      Clear (Result);
      for V in 1 .. NW loop
         W.Remap (V) := 0;
      end loop;
      for I in 1 .. NP loop
         for E in 0 .. W.Len_2 (I) - 1 loop
            declare
               X : constant Count := W.Loop_2 (W.Start_2 (I) + E);
            begin
               if W.Remap (X) = 0 then
                  Add_Vertex (Result, To_Vec3 (W.Pos (X)), W.Remap (X), Ok);
                  if not Ok then
                     raise Result_Too_Big;
                  end if;
               end if;
            end;
         end loop;
      end loop;
      for I in 1 .. NP loop
         if W.Len_2 (I) >= 3 then
            Fan (I);
         end if;
      end loop;
   end Emit;

   procedure Append_Mesh (Result : in out Tri_Mesh; M : Tri_Mesh) is
      Base : constant Vertex_Index := Result.NV;
      Ix   : Vertex_Index;
      Ok   : Boolean;
   begin
      for I in 1 .. M.NV loop
         Add_Vertex (Result, M.V (I), Ix, Ok);
         if not Ok then
            raise Result_Too_Big;
         end if;
         pragma Assert (Ix = Base + I);
      end loop;
      for I in 1 .. M.NT loop
         Add_Triangle (Result, Base + M.T (I).A, Base + M.T (I).B, Base + M.T (I).C, Ok);
         if not Ok then
            raise Result_Too_Big;
         end if;
      end loop;
   end Append_Mesh;

   procedure Say (Reason : out Reason_String; Last : out Natural; Msg : String) is
      N : constant Natural := Natural'Min (Msg'Length, Max_Reason);
   begin
      Reason := [others => ' '];
      Reason (1 .. N) := Msg (Msg'First .. Msg'First + N - 1);
      Last := N;
   end Say;

   ---------------------------------------------------------------------
   --  Public
   ---------------------------------------------------------------------

   procedure Size_For
     (Triangles : Triangle_Index; Factor : Positive; Polygons, Points, Nodes : out Count)
   is
      Limit : constant Long_Long_Integer := Long_Long_Integer (Count'Last) / 8;
      Want  : constant Long_Long_Integer :=
        (4 * Long_Long_Integer (Triangles) + 256) * Long_Long_Integer (Factor);
      P     : constant Count := Count (Long_Long_Integer'Min (Want, Limit));
   begin
      Polygons := P;
      Points := 8 * P;
      Nodes := P;
   end Size_For;

   procedure Apply
     (Op     : Operation;
      A, B   : Tri_Mesh;
      Result : in out Tri_Mesh;
      Work   : in out Workspace;
      Check  : in out Validity.Workspace;
      Status : out Outcome;
      Reason : out Reason_String;
      Last   : out Natural)
   is
      Rep  : Validity.Report;
      List : Count;

      procedure Fail (S : Outcome; Msg : String);
      procedure Fail (S : Outcome; Msg : String) is
      begin
         Clear (Result);
         Status := S;
         Say (Reason, Last, Msg);
      end Fail;

   begin
      Clear (Result);
      Status := Success;
      Say (Reason, Last, "");

      Validity.Inspect (A, Check, Rep);
      if not Rep.Solid then
         Fail (Input_Not_Solid, "first input is not a solid: " & Validity.Problem (Rep));
         return;
      end if;
      Validity.Inspect (B, Check, Rep);
      if not Rep.Solid then
         Fail (Input_Not_Solid, "second input is not a solid: " & Validity.Problem (Rep));
         return;
      end if;
      if (for some I in 1 .. A.NV => not Fits (A.V (I)))
        or else (for some I in 1 .. B.NV => not Fits (B.V (I)))
      then
         Fail (Out_Of_Range, "a coordinate is beyond the exact range (about 32 m)");
         return;
      end if;

      Work.Pool_N := 0;
      Work.Polys_N := 0;
      Work.Nodes_N := 0;
      Load (Work, A, 1);
      Load (Work, B, 2);

      if Big (Work.Hi (1).X) < Big (Work.Lo (2).X) - Weld_Steps
        or else Big (Work.Hi (2).X) < Big (Work.Lo (1).X) - Weld_Steps
        or else Big (Work.Hi (1).Y) < Big (Work.Lo (2).Y) - Weld_Steps
        or else Big (Work.Hi (2).Y) < Big (Work.Lo (1).Y) - Weld_Steps
        or else Big (Work.Hi (1).Z) < Big (Work.Lo (2).Z) - Weld_Steps
        or else Big (Work.Hi (2).Z) < Big (Work.Lo (1).Z) - Weld_Steps
      then
         --  Boxes apart: no cutting needed.
         case Op is
            when Union =>
               Append_Mesh (Result, A);
               Append_Mesh (Result, B);
            when Difference =>
               Append_Mesh (Result, A);
            when Intersection =>
               Fail (Empty_Result, "result is empty: the solids do not overlap");
               return;
         end case;
      else
         --  The csg.js recipes (tree 1 = A, tree 2 = B). The double invert
         --  of B keeps a face the two share only once.
         case Op is
            when Union =>
               Clip_Tree (Work, 1, 2);
               Clip_Tree (Work, 2, 1);
               Invert (Work, 2);
               Clip_Tree (Work, 2, 1);
               Invert (Work, 2);
               Take_All (Work, 2, List);
               Build (Work, Work.Roots (1), List);
               Take_All (Work, 1, List);
            when Difference =>
               Invert (Work, 1);
               Clip_Tree (Work, 1, 2);
               Clip_Tree (Work, 2, 1);
               Invert (Work, 2);
               Clip_Tree (Work, 2, 1);
               Invert (Work, 2);
               Take_All (Work, 2, List);
               Build (Work, Work.Roots (1), List);
               Invert (Work, 1);
               Take_All (Work, 1, List);
            when Intersection =>
               Invert (Work, 1);
               Clip_Tree (Work, 2, 1);
               Invert (Work, 2);
               Clip_Tree (Work, 1, 2);
               Clip_Tree (Work, 2, 1);
               Take_All (Work, 2, List);
               Build (Work, Work.Roots (1), List);
               Invert (Work, 1);
               Take_All (Work, 1, List);
         end case;
         if List = 0 then
            Fail (Empty_Result, "result is empty: nothing is left");
            return;
         end if;
         Emit (Work, List, Result);
      end if;

      if Result.NT = 0 then
         Fail (Empty_Result, "result is empty: nothing is left");
         return;
      end if;
      Validity.Inspect (Result, Check, Rep);
      if not Rep.Solid then
         --  Usually the true answer is zero-thick somewhere (solids touching
         --  along a line or at a point); deep in a chain of booleans it can
         --  be a sliver as thin as Weld_Steps. Nothing broken is returned.
         if Rep.Open_Edges > 0 then
            Fail (Result_Not_Solid, "result has a crack: " & Validity.Problem (Rep));
         elsif Rep.Repeated_Edges > 0 or else Rep.Nonmanifold_Vertices > 0 then
            Fail (Result_Not_Solid,
                  "result pinches to an edge or a point: " & Validity.Problem (Rep));
         else
            Fail (Result_Not_Solid, "result is not a solid: " & Validity.Problem (Rep));
         end if;
      end if;
   exception
      when Out_Of_Room =>
         Fail (Workspace_Full, "the boolean ran out of working memory");
      when Result_Too_Big =>
         Fail (Result_Full, "the result has more triangles than a solid can hold");
   end Apply;

end Forge.CSG;
