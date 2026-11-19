with Forge.Exact;

package body Forge.Validity with SPARK_Mode => Off is
   --  Off for the square root in the area. No heap, no recursion.

   type Edge_Key is range 0 .. 2 ** 50;
   --  Directed edge (from, to) as from * 2**25 + to, which keeps the order.

   --  Edge E is corner (E - 1) mod 3 (A->B, B->C, C->A) of triangle (E + 2) / 3.
   function Triangle_Of (E : Edge_Count) return Triangle_Index is
     (Triangle_Index ((E + 2) / 3));
   function Corner_Of (E : Edge_Count) return Edge_Count is ((E - 1) mod 3);
   function Next_In_Triangle (E : Edge_Count) return Edge_Count is
     (if Corner_Of (E) = 2 then E - 2 else E + 1);
   function Pack (Tail, Head : Vertex_Index) return Edge_Key is
     (Edge_Key (Tail) * 2 ** 25 + Edge_Key (Head));

   procedure Ends (M : Tri_Mesh; E : Edge_Count; From, To : out Vertex_Index);
   function Key (M : Tri_Mesh; E : Edge_Count) return Edge_Key;
   procedure Sort (M : Tri_Mesh; W : in out Workspace; N : Edge_Count);
   function First_At_Least
     (M : Tri_Mesh; W : Workspace; N : Edge_Count; K : Edge_Key) return Edge_Count;
   procedure Find (W : in out Workspace; X : Edge_Count; Root : out Edge_Count);
   procedure Join (W : in out Workspace; A, B : Edge_Count);
   procedure Measure (M : Tri_Mesh; R : in out Report);

   procedure Ends (M : Tri_Mesh; E : Edge_Count; From, To : out Vertex_Index) is
      T : constant Triangle := M.T (Triangle_Of (E));
   begin
      case Corner_Of (E) is
         when 0      => From := T.A; To := T.B;
         when 1      => From := T.B; To := T.C;
         when others => From := T.C; To := T.A;
      end case;
   end Ends;

   function Key (M : Tri_Mesh; E : Edge_Count) return Edge_Key is
      From, To : Vertex_Index;
   begin
      Ends (M, E, From, To);
      return Pack (From, To);
   end Key;

   --  Heap sort of W.Order (1 .. N) by edge key: in place, no recursion,
   --  O(N log N) whatever the input order.
   procedure Sort (M : Tri_Mesh; W : in out Workspace; N : Edge_Count) is
      procedure Swap (I, J : Edge_Count);
      procedure Sift (Start, Stop : Edge_Count);

      procedure Swap (I, J : Edge_Count) is
         T : constant Edge_Count := W.Order (I);
      begin
         W.Order (I) := W.Order (J);
         W.Order (J) := T;
      end Swap;

      procedure Sift (Start, Stop : Edge_Count) is
         Root  : Edge_Count := Start;
         Child : Edge_Count;
      begin
         while Root <= Stop / 2 loop
            Child := 2 * Root;
            if Child < Stop and then Key (M, W.Order (Child)) < Key (M, W.Order (Child + 1)) then
               Child := Child + 1;
            end if;
            exit when Key (M, W.Order (Root)) >= Key (M, W.Order (Child));
            Swap (Root, Child);
            Root := Child;
         end loop;
      end Sift;

   begin
      for Start in reverse 1 .. N / 2 loop
         Sift (Start, N);
      end loop;
      for Stop in reverse 2 .. N loop
         Swap (1, Stop);
         Sift (1, Stop - 1);
      end loop;
   end Sort;

   --  First position P in 1 .. N + 1 whose key is >= K (binary search).
   function First_At_Least
     (M : Tri_Mesh; W : Workspace; N : Edge_Count; K : Edge_Key) return Edge_Count
   is
      Lo  : Edge_Count := 1;
      Hi  : Edge_Count := N + 1;
      Mid : Edge_Count;
   begin
      while Lo < Hi loop
         Mid := Lo + (Hi - Lo) / 2;
         if Key (M, W.Order (Mid)) < K then
            Lo := Mid + 1;
         else
            Hi := Mid;
         end if;
      end loop;
      return Lo;
   end First_At_Least;

   procedure Find (W : in out Workspace; X : Edge_Count; Root : out Edge_Count) is
      Y : Edge_Count := X;
   begin
      while W.Parent (Y) /= Y loop
         W.Parent (Y) := W.Parent (W.Parent (Y));  --  path halving
         Y := W.Parent (Y);
      end loop;
      Root := Y;
   end Find;

   procedure Join (W : in out Workspace; A, B : Edge_Count) is
      RA, RB : Edge_Count;
   begin
      Find (W, A, RA);
      Find (W, B, RB);
      if RA /= RB then
         W.Parent (RA) := RB;
      end if;
   end Join;

   --  Volume (exact, in a Wide, so its sign is the true sign), area and
   --  triangle quality.
   procedure Measure (M : Tri_Mesh; R : in out Report) is
      use Exact;
      Total : Wide := Zero;
   begin
      for V in 1 .. M.NV loop
         if not Fits (M.V (V)) then
            --  Beyond the exact range: fall back to the rounded volume.
            R.Volume := Volume (M);
            return;
         end if;
      end loop;
      for I in 1 .. M.NT loop
         declare
            A : constant Point := To_Point (M.V (M.T (I).A));
            B : constant Point := To_Point (M.V (M.T (I).B));
            C : constant Point := To_Point (M.V (M.T (I).C));
            N : constant Vector := Cross (B - A, C - A);   --  twice the area, in steps**2
            Longest : constant Big :=
              Big'Max (Max_Abs (B - A), Big'Max (Max_Abs (C - B), Max_Abs (A - C)));
         begin
            Total := Total + Dot (Cross (As_Vector (B), As_Vector (C)), As_Vector (A));
            if Is_Zero (N) then
               R.Degenerate := R.Degenerate + 1;
            else
               --  Height under 1/1000 of the longest edge (to a factor of 3).
               if 1000 * Max_Abs (N) < Longest * Longest then
                  R.Slivers := R.Slivers + 1;
               end if;
               R.Area := R.Area
                 + Length ((To_Scalar (N.X / 2 ** 32), To_Scalar (N.Y / 2 ** 32),
                            To_Scalar (N.Z / 2 ** 32))) / 2;
            end if;
         end;
      end loop;
      --  Total is 6 * volume in units of 2**-96 mm**3.
      R.Volume := To_Scalar (High (Total) / 6);
   end Measure;

   procedure Inspect (M : Tri_Mesh; W : in out Workspace; R : out Report) is
      N           : constant Edge_Count := Edges_For (M.NT);
      From, To    : Vertex_Index;
      First, Last : Edge_Count;
      Root        : Edge_Count;
   begin
      R := (others => <>);
      R.Triangles := M.NT;

      --  Corners per vertex, and every edge id in order with no twin yet.
      for V in 1 .. M.NV loop
         W.Corners (V) := 0;
         W.Fans (V) := 0;
      end loop;
      for E in 1 .. N loop
         Ends (M, E, From, To);
         W.Corners (From) := W.Corners (From) + 1;
         W.Order (E) := E;
         W.Twin (E) := 0;
         W.Seen (E) := False;
      end loop;
      for V in 1 .. M.NV loop
         if W.Corners (V) > 0 then
            R.Vertices := R.Vertices + 1;
         end if;
      end loop;

      --  Sorted: copies of an edge are adjacent; its twin, a binary search.
      Sort (M, W, N);
      First := 1;
      while First <= N loop
         Last := First;
         while Last < N and then Key (M, W.Order (Last + 1)) = Key (M, W.Order (First)) loop
            Last := Last + 1;
         end loop;
         Ends (M, W.Order (First), From, To);
         R.Repeated_Edges := R.Repeated_Edges + (Last - First);
         declare
            Back  : constant Edge_Key := Pack (To, From);
            Pos   : constant Edge_Count := First_At_Least (M, W, N, Back);
            Found : constant Boolean := Pos <= N and then Key (M, W.Order (Pos)) = Back;
         begin
            if Found then
               for P in First .. Last loop
                  W.Twin (W.Order (P)) := W.Order (Pos);
               end loop;
            else
               R.Open_Edges := R.Open_Edges + (Last - First + 1);
            end if;
            --  Each undirected edge once.
            if From < To or else not Found then
               R.Edges := R.Edges + 1;
            end if;
         end;
         First := Last + 1;
      end loop;
      R.Watertight := R.Open_Edges = 0 and then R.Repeated_Edges = 0;

      --  Shells: triangles joined across shared edges.
      for T in 1 .. M.NT loop
         W.Parent (Edge_Count (T)) := Edge_Count (T);
      end loop;
      for E in 1 .. N loop
         if W.Twin (E) /= 0 then
            Join (W, Edge_Count (Triangle_Of (E)), Edge_Count (Triangle_Of (W.Twin (E))));
         end if;
      end loop;
      for T in 1 .. M.NT loop
         Find (W, Edge_Count (T), Root);
         if Root = Edge_Count (T) then
            R.Shells := R.Shells + 1;
         end if;
      end loop;

      --  Fans: from edge V->X, cross to its twin X->V and take that
      --  triangle's next edge, which leaves V again. A vertex needing more
      --  than one such cycle is where two cones of triangles meet.
      if R.Watertight then
         for E in 1 .. N loop
            if not W.Seen (E) then
               Ends (M, E, From, To);
               W.Fans (From) := W.Fans (From) + 1;
               declare
                  C     : Edge_Count := E;
                  Steps : Edge_Count := 0;
               begin
                  loop
                     W.Seen (C) := True;
                     C := Next_In_Triangle (W.Twin (C));
                     Steps := Steps + 1;
                     exit when C = E or else Steps >= N;
                  end loop;
               end;
            end if;
         end loop;
         for V in 1 .. M.NV loop
            if W.Fans (V) > 1 then
               R.Nonmanifold_Vertices := R.Nonmanifold_Vertices + 1;
            end if;
         end loop;
         R.Manifold := R.Nonmanifold_Vertices = 0;
      end if;

      --  For a closed orientable surface, Euler = 2 * (shells - genus).
      R.Euler := Integer (R.Vertices) - Integer (R.Edges) + Integer (M.NT);
      if R.Manifold then
         R.Genus := (2 * Integer (R.Shells) - R.Euler) / 2;
      end if;

      Measure (M, R);
      R.Solid := M.NT >= 4 and then R.Manifold and then R.Volume > 0.0;
   end Inspect;

   function Problem (R : Report) return String is
      function Img (N : Natural) return String;
      function Count_Of (N : Natural; One, Many : String) return String;

      function Img (N : Natural) return String is
         S : constant String := N'Image;
      begin
         return S (S'First + 1 .. S'Last);
      end Img;

      function Count_Of (N : Natural; One, Many : String) return String is
        (Img (N) & " " & (if N = 1 then One else Many));

   begin
      if R.Solid then
         return "";
      elsif R.Triangles < 4 then
         return "fewer than 4 triangles";
      elsif R.Open_Edges > 0 then
         return Count_Of (Natural (R.Open_Edges), "open edge", "open edges");
      elsif R.Repeated_Edges > 0 then
         return Count_Of (Natural (R.Repeated_Edges), "repeated edge", "repeated edges");
      elsif R.Nonmanifold_Vertices > 0 then
         return Count_Of (Natural (R.Nonmanifold_Vertices),
                          "nonmanifold vertex", "nonmanifold vertices");
      else
         return "inside out (volume is not positive)";
      end if;
   end Problem;

end Forge.Validity;
