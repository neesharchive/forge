with Ada.Exceptions;
with Forge.Numeric;
with Forge.Validation;
package body Forge.CSG with SPARK_Mode => Off is
   --  Bounded BSP reference evaluator. Proof coverage is recorded separately.
   --  Algorithm: Evan Wallace's MIT-licensed csg.js (2011), clip/invert/build.
   Capacity_Error, Precision_Error : exception;
   Eps : constant Scalar := Numeric.Epsilon;

   procedure Apply
     (Op : Operation; A, B : Tri_Mesh; Result : in out Tri_Mesh;
      Ok : out Boolean; Reason : out Reason_String; Last : out Natural;
      Work : in out Workspace)
   is
      W : Workspace renames Work;
      RA, RB, PA, PB : Natural := 0;
      Validity : Validation.Status;
      Shells : Natural;
      use type Validation.Status;

      procedure Fail (S : String);

      procedure Fail (S : String) is
      begin
         Clear (Result);
         Ok := False;
         Reason := [others => ' '];
         Last := Natural'Min (S'Length, Max_Reason);
         Reason (1 .. Last) := S (S'First .. S'First + Last - 1);
      end Fail;

      function New_Polygon (P : Polygon) return Natural;

      function New_Polygon (P : Polygon) return Natural is
      begin
         if W.Used_P = Max_Polygons then
            raise Capacity_Error with "polygon pool";
         end if;
         W.Used_P := W.Used_P + 1;
         W.P (W.Used_P) := P;
         return W.Used_P;
      end New_Polygon;

      procedure Push (Head : in out Natural; P : Natural);

      procedure Push (Head : in out Natural; P : Natural) is
      begin
         W.P (P).Next := Head;
         Head := P;
      end Push;

      procedure Append (Head : in out Natural; Other : Natural);

      procedure Append (Head : in out Natural; Other : Natural) is
         I : Natural := Other;
         J : Natural;
      begin
         while I /= 0 loop
            J := W.P (I).Next;
            Push (Head, I);
            I := J;
         end loop;
      end Append;

      procedure Corner (P : in out Polygon; V : Vec3);

      procedure Corner (P : in out Polygon; V : Vec3) is
      begin
         if P.Count > 0 and then Numeric.Close (P.V (P.Count), V) then
            return;
         end if;
         if P.Count = Max_Corners then
            raise Capacity_Error with "polygon corners";
         end if;
         P.Count := P.Count + 1;
         P.V (P.Count) := V;
      end Corner;

      procedure Split (N : BSP_Node; Id : Natural;
                       CF, CB, F, Bk : in out Natural);

      procedure Split (N : BSP_Node; Id : Natural;
                       CF, CB, F, Bk : in out Natural)
      is
         P : constant Polygon := W.P (Id);
         FP, BP : Polygon;
         type Class_Array is array (1 .. Max_Corners) of Integer;
         C : Class_Array := [others => 0];
         Has_F, Has_B : Boolean := False;
         D : Scalar;
         J : Positive;
         V : Vec3;
         T, Den : Scalar;
      begin
         for I in 1 .. P.Count loop
            D := Dot (N.Normal, P.V (I)) - N.W;
            if D > Eps then
               C (I) := 1;
               Has_F := True;
            elsif D < -Eps then
               C (I) := -1;
               Has_B := True;
            end if;
         end loop;
         if not Has_F and then not Has_B then
            if Dot (N.Normal, P.Normal) > 0.0 then
               Push (CF, Id);
            else
               Push (CB, Id);
            end if;
         elsif not Has_B then
            Push (F, Id);
         elsif not Has_F then
            Push (Bk, Id);
         else
            FP.Normal := P.Normal; FP.W := P.W;
            BP.Normal := P.Normal; BP.W := P.W;
            for I in 1 .. P.Count loop
               J := (if I = P.Count then 1 else I + 1);
               if C (I) >= 0 then
                  Corner (FP, P.V (I));
               end if;
               if C (I) <= 0 then
                  Corner (BP, P.V (I));
               end if;
               if C (I) * C (J) = -1 then
                  Den := Dot (N.Normal, P.V (J) - P.V (I));
                  if Den = 0.0 then
                     raise Precision_Error;
                  end if;
                  T := (N.W - Dot (N.Normal, P.V (I))) / Den;
                  V := P.V (I) + (P.V (J) - P.V (I)) * T;
                  --  Axis planes have exactly representable constraints. Keep
                  --  their coordinate exact after rounding interpolation.
                  if N.Normal.Y = 0.0 and then N.Normal.Z = 0.0 then
                     V.X := N.W / N.Normal.X;
                  elsif N.Normal.X = 0.0 and then N.Normal.Z = 0.0 then
                     V.Y := N.W / N.Normal.Y;
                  elsif N.Normal.X = 0.0 and then N.Normal.Y = 0.0 then
                     V.Z := N.W / N.Normal.Z;
                  end if;
                  if not Numeric.Valid (V) then
                     raise Precision_Error;
                  end if;
                  Corner (FP, V); Corner (BP, V);
               end if;
            end loop;
            if FP.Count > 1 and then Numeric.Close (FP.V (1), FP.V (FP.Count)) then
               FP.Count := FP.Count - 1;
            end if;
            if BP.Count > 1 and then Numeric.Close (BP.V (1), BP.V (BP.Count)) then
               BP.Count := BP.Count - 1;
            end if;
            if FP.Count < 3 or else BP.Count < 3 then
               raise Precision_Error;
            end if;
            W.P (Id) := FP;
            Push (F, Id);
            Push (Bk, New_Polygon (BP));
         end if;
      end Split;

      procedure Build (Root : in out Natural; Polys : Natural; Depth : Natural := 0);

      procedure Build (Root : in out Natural; Polys : Natural; Depth : Natural := 0) is
         F, Bk : Natural := 0;
         I : Natural := Polys;
         J, CF, CB : Natural;
      begin
         if I = 0 then
            return;
         end if;
         if Depth > 512 then
            raise Capacity_Error with "depth or mesh output";
         end if;
         if Root = 0 then
            if W.Used_N = Max_Nodes then
               raise Capacity_Error with "splitter nodes";
            end if;
            W.Used_N := W.Used_N + 1;
            Root := W.Used_N;
            W.N (Root) := (Normal => W.P (I).Normal, W => W.P (I).W, others => <>);
         end if;
         CF := W.N (Root).Polys; CB := CF;
         while I /= 0 loop
            J := W.P (I).Next;
            --  Both coplanar orientations belong to this splitter node.
            CB := 0;
            Split (W.N (Root), I, CF, CB, F, Bk);
            Append (CF, CB);
            I := J;
         end loop;
         W.N (Root).Polys := CF;
         Build (W.N (Root).Front, F, Depth + 1);
         Build (W.N (Root).Back, Bk, Depth + 1);
      end Build;

      function Clip (Root, Polys : Natural; Depth : Natural := 0) return Natural;

      function Clip (Root, Polys : Natural; Depth : Natural := 0) return Natural is
         F, Bk : Natural := 0;
         I : Natural := Polys;
         J, CF, CB : Natural;
      begin
         if Root = 0 then
            return Polys;
         end if;
         if Depth > 512 then
            raise Capacity_Error with "depth or mesh output";
         end if;
         while I /= 0 loop
            J := W.P (I).Next;
            CF := 0; CB := 0;
            Split (W.N (Root), I, CF, CB, F, Bk);
            Append (F, CF); Append (Bk, CB);
            I := J;
         end loop;
         F := Clip (W.N (Root).Front, F, Depth + 1);
         if W.N (Root).Back /= 0 then
            Bk := Clip (W.N (Root).Back, Bk, Depth + 1);
         else
            Bk := 0;
         end if;
         Append (F, Bk);
         return F;
      end Clip;

      procedure Clip_To (Root, Other : Natural; Depth : Natural := 0);

      procedure Clip_To (Root, Other : Natural; Depth : Natural := 0) is
      begin
         if Root = 0 then
            return;
         end if;
         if Depth > 512 then
            raise Capacity_Error with "depth or mesh output";
         end if;
         W.N (Root).Polys := Clip (Other, W.N (Root).Polys);
         Clip_To (W.N (Root).Front, Other, Depth + 1);
         Clip_To (W.N (Root).Back, Other, Depth + 1);
      end Clip_To;

      procedure Invert (Root : Natural; Depth : Natural := 0);

      procedure Invert (Root : Natural; Depth : Natural := 0) is
         I : Natural;
         Temp : Vec3;
         J : Natural;
      begin
         if Root = 0 then
            return;
         end if;
         if Depth > 512 then
            raise Capacity_Error with "depth or mesh output";
         end if;
         W.N (Root).Normal := -W.N (Root).Normal;
         W.N (Root).W := -W.N (Root).W;
         I := W.N (Root).Polys;
         while I /= 0 loop
            for K in 1 .. W.P (I).Count / 2 loop
               J := W.P (I).Count + 1 - K;
               Temp := W.P (I).V (K);
               W.P (I).V (K) := W.P (I).V (J);
               W.P (I).V (J) := Temp;
            end loop;
            W.P (I).Normal := -W.P (I).Normal;
            W.P (I).W := -W.P (I).W;
            I := W.P (I).Next;
         end loop;
         J := W.N (Root).Front;
         W.N (Root).Front := W.N (Root).Back;
         W.N (Root).Back := J;
         Invert (W.N (Root).Front, Depth + 1);
         Invert (W.N (Root).Back, Depth + 1);
      end Invert;

      procedure Gather (Root : Natural; List : in out Natural; Depth : Natural := 0);

      procedure Gather (Root : Natural; List : in out Natural; Depth : Natural := 0) is
      begin
         if Root = 0 then
            return;
         end if;
         if Depth > 512 then
            raise Capacity_Error with "depth or mesh output";
         end if;
         Append (List, W.N (Root).Polys);
         Gather (W.N (Root).Front, List, Depth + 1);
         Gather (W.N (Root).Back, List, Depth + 1);
      end Gather;

      procedure Import (M : Tri_Mesh; List : out Natural);

      procedure Import (M : Tri_Mesh; List : out Natural) is
         P : Polygon;
         N : Scalar;
      begin
         List := 0;
         for I in 1 .. M.NT loop
            P := (others => <>);
            P.Count := 3;
            P.V (1) := M.V (M.T (I).A);
            P.V (2) := M.V (M.T (I).B);
            P.V (3) := M.V (M.T (I).C);
            P.Normal := Normal (M, I);
            N := Length (P.Normal);
            if N = 0.0 then
               raise Precision_Error;
            end if;
            P.Normal := P.Normal * (1.0 / N);
            P.W := Dot (P.Normal, P.V (1));
            Push (List, New_Polygon (P));
         end loop;
      end Import;

      procedure Emit (List : Natural);

      procedure Emit (List : Natural) is
         I : Natural := List;
         Good : Boolean;
         Dummy, Center, VA, VB : Vertex_Index;
         Boundary_Count : Vertex_Index;
         P, Q, D, Mid : Vec3;
         Len2, T, Best, Prev : Scalar;
         Found : Vertex_Index;

         function Vertex (V : Vec3) return Vertex_Index;

         function Vertex (V : Vec3) return Vertex_Index is
            Id : Vertex_Index;
         begin
            if not Numeric.Valid (V) then
               raise Precision_Error;
            end if;
            for K in 1 .. Result.NV loop
               if Numeric.Close (Result.V (K), V) then
                  return K;
               end if;
            end loop;
            Add_Vertex (Result, V, Id, Good);
            if not Good then
               raise Capacity_Error with "depth or mesh output";
            end if;
            return Id;
         end Vertex;
      begin
         --  Establish all boundary vertices before triangulating, so every
         --  shared edge is subdivided at every intervening vertex.
         while I /= 0 loop
            for K in 1 .. W.P (I).Count loop
               Dummy := Vertex (W.P (I).V (K));
            end loop;
            I := W.P (I).Next;
         end loop;
         Boundary_Count := Result.NV;
         I := List;
         while I /= 0 loop
            Mid := Origin;
            for K in 1 .. W.P (I).Count loop
               Mid := Mid + W.P (I).V (K);
            end loop;
            Mid := Mid / Scalar (W.P (I).Count);
            Center := Vertex (Mid);
            for K in 1 .. W.P (I).Count loop
               P := W.P (I).V (K);
               Q := W.P (I).V ((if K = W.P (I).Count then 1 else K + 1));
               D := Q - P; Len2 := Dot (D, D);
               if Len2 = 0.0 then
                  raise Precision_Error;
               end if;
               VA := Vertex (P); VB := Vertex (Q); Prev := 0.0;
               loop
                  Best := 1.0; Found := VB;
                  for J in 1 .. Boundary_Count loop
                     T := Dot (Result.V (J) - P, D) / Len2;
                     if T > Prev + Eps / Length (D) and then T < Best - Eps / Length (D)
                       and then Length (Result.V (J) - (P + D * T)) <= Eps
                     then
                        Best := T; Found := J;
                     end if;
                  end loop;
                  if VA = Found or else VA = Center or else Found = Center then
                     raise Precision_Error;
                  end if;
                  Add_Triangle (Result, Center, VA, Found, Good);
                  if not Good then
                     raise Capacity_Error with "depth or mesh output";
                  end if;
                  exit when Found = VB;
                  VA := Found; Prev := Best;
               end loop;
            end loop;
            I := W.P (I).Next;
         end loop;
         if Result.NT = 0 then
            Clear (Result);
         end if;
      end Emit;
   begin
      W.Used_P := 0; W.Used_N := 0;
      Clear (Result); Ok := False; Reason := [others => ' ']; Last := 0;
      Validation.Check (A, Validity, Shells);
      if Validity not in Validation.Valid | Validation.Empty then
         Fail ("invalid input A: " & Validity'Image); return;
      end if;
      Validation.Check (B, Validity, Shells);
      if Validity not in Validation.Valid | Validation.Empty then
         Fail ("invalid input B: " & Validity'Image); return;
      end if;
      if A.NT = 0 and then B.NT = 0 then
         Ok := True; return;
      end if;
      if A.NT = 0 or else B.NT = 0 then
         if Op = Union or else (Op = Difference and then B.NT = 0) then
            Copy ((if A.NT = 0 then B else A), Result, Ok);
         else
            Ok := True;
         end if;
         if not Ok then
            Fail ("capacity exceeded: result mesh");
         end if;
         return;
      end if;
      if not Is_Solid (A) or else not Is_Solid (B) then
         Fail ("invalid input: open or inconsistent mesh"); return;
      end if;
      Import (A, PA); Import (B, PB);
      Build (RA, PA); Build (RB, PB);
      case Op is
         when Union =>
            Clip_To (RA, RB); Clip_To (RB, RA);
            Invert (RB); Clip_To (RB, RA); Invert (RB);
            PB := 0; Gather (RB, PB); Build (RA, PB);
         when Difference =>
            Invert (RA); Clip_To (RA, RB); Clip_To (RB, RA);
            Invert (RB); Clip_To (RB, RA); Invert (RB);
            PB := 0; Gather (RB, PB); Build (RA, PB); Invert (RA);
         when Intersection =>
            Invert (RA); Clip_To (RB, RA); Invert (RB);
            Clip_To (RA, RB); Clip_To (RB, RA);
            PB := 0; Gather (RB, PB); Build (RA, PB); Invert (RA);
      end case;
      PA := 0; Gather (RA, PA); Emit (PA);
      Validation.Check (Result, Validity, Shells);
      if Validity not in Validation.Valid | Validation.Empty then
         Fail ("invalid output: " & Validity'Image);
      else
         Ok := True;
      end if;
   exception
      when E : Capacity_Error =>
         Fail ("capacity exceeded: " & Ada.Exceptions.Exception_Message (E));
      when Precision_Error => Fail ("precision insufficient: polygon reconstruction");
   end Apply;
end Forge.CSG;
