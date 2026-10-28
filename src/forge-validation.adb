with Ada.Numerics.Generic_Elementary_Functions;
with Forge.Numeric;
package body Forge.Validation with SPARK_Mode => Off is
   use Mesh;
   Tol : constant Scalar := Numeric.Epsilon;

   procedure Check (M : Tri_Mesh; Result : out Status; Shells : out Natural) is
      Cap : constant Triangle_Index := Triangle_Index'Min (M.NT, Max_Triangles);
      type Face_Array is array (Triangle_Index range <>) of Natural;
      Component : Face_Array (1 .. Cap) := [others => 0];
      Queue : array (Triangle_Index range 1 .. Cap) of Triangle_Index;
      Signed_Volume : array (Triangle_Index range 1 .. Cap) of Scalar := [others => 0.0];
      Samples : array (Triangle_Index range 1 .. Cap) of Vertex_Index := [others => 0];
      First, Last : Triangle_Index;

      function Corner (I : Triangle_Index; K : Positive) return Vertex_Index;
      function Shared (I, J : Triangle_Index) return Natural;
      function Allowed (P : Vec3; I, J : Triangle_Index) return Boolean;
      function Crossing (I, J : Triangle_Index) return Boolean;
      function Inside (P : Vec3; Shell : Natural) return Boolean;

      function Corner (I : Triangle_Index; K : Positive) return Vertex_Index is
        (case K is when 1 => M.T (I).A, when 2 => M.T (I).B, when others => M.T (I).C);

      function Shared (I, J : Triangle_Index) return Natural is
         N : Natural := 0;
      begin
         for K in 1 .. 3 loop
            for L in 1 .. 3 loop
               if Corner (I, K) = Corner (J, L) then
                  N := N + 1;
               end if;
            end loop;
         end loop;
         return N;
      end Shared;

      function Allowed (P : Vec3; I, J : Triangle_Index) return Boolean is
         A, B : Vec3 := Origin;
         Count : Natural := 0;
      begin
         if not Numeric.Valid (P) then
            return False;
         end if;
         for K in 1 .. 3 loop
            for L in 1 .. 3 loop
               if Corner (I, K) = Corner (J, L) then
                  Count := Count + 1;
                  if Count = 1 then
                     A := M.V (Corner (I, K));
                  else
                     B := M.V (Corner (I, K));
                  end if;
                  if Numeric.Close (P, M.V (Corner (I, K))) then
                     return True;
                  end if;
               end if;
            end loop;
         end loop;
         if Count = 2 then
            declare
               D : constant Vec3 := B - A;
               T : constant Scalar := Dot (P - A, D) / Dot (D, D);
            begin
               return T >= -Tol and then T <= 1.0 + Tol
                 and then Length (P - (A + D * T)) <= Tol;
            end;
         end if;
         return False;
      end Allowed;

      function Crossing (I, J : Triangle_Index) return Boolean is
         type Points is array (1 .. 3) of Vec3;
         A, B : Points;
         NA, NB : Vec3;
         Drop : Positive := 1;

         function Orient (P, Q, R : Vec3) return Scalar;
         function Strict_Inside (P : Vec3; T : Points) return Boolean;
         function Segment_Hit (P, Q : Vec3; T : Points) return Boolean;

         function Orient (P, Q, R : Vec3) return Scalar is
         begin
            case Drop is
               when 1 => return (Q.Y - P.Y) * (R.Z - P.Z) - (Q.Z - P.Z) * (R.Y - P.Y);
               when 2 => return (Q.X - P.X) * (R.Z - P.Z) - (Q.Z - P.Z) * (R.X - P.X);
               when others => return (Q.X - P.X) * (R.Y - P.Y) - (Q.Y - P.Y) * (R.X - P.X);
            end case;
         end Orient;

         function Strict_Inside (P : Vec3; T : Points) return Boolean is
            X : constant Scalar := Orient (T (1), T (2), P);
            Y : constant Scalar := Orient (T (2), T (3), P);
            Z : constant Scalar := Orient (T (3), T (1), P);
            Bound : constant Scalar := Tol * Scalar'Max
              (Length (T (2) - T (1)), Scalar'Max
                 (Length (T (3) - T (2)), Length (T (1) - T (3))));
         begin
            return (X > Bound and then Y > Bound and then Z > Bound)
              or else (X < -Bound and then Y < -Bound and then Z < -Bound);
         end Strict_Inside;

         function Segment_Hit (P, Q : Vec3; T : Points) return Boolean is
            D : constant Vec3 := Q - P;
            E1 : constant Vec3 := T (2) - T (1);
            E2 : constant Vec3 := T (3) - T (1);
            H : constant Vec3 := Cross (D, E2);
            Det : constant Scalar := Dot (E1, H);
            S, QV : Vec3;
            U, V, Ray_T : Scalar;
         begin
            if abs Det <= 1.0e-12 * Length (E1) * Length (H) then
               return False;
            end if;
            S := P - T (1); U := Dot (S, H) / Det;
            QV := Cross (S, E1); V := Dot (D, QV) / Det;
            Ray_T := Dot (E2, QV) / Det;
            return U >= -1.0e-10 and then V >= -1.0e-10
              and then U + V <= 1.0 + 1.0e-10
              and then Ray_T >= -1.0e-10 and then Ray_T <= 1.0 + 1.0e-10
              and then not Allowed (P + D * Ray_T, I, J);
         end Segment_Hit;
      begin
         for K in 1 .. 3 loop
            A (K) := M.V (Corner (I, K)); B (K) := M.V (Corner (J, K));
         end loop;
         --  Broad-phase rejection before intersection arithmetic.
         if Scalar'Max (A (1).X, Scalar'Max (A (2).X, A (3).X)) + Tol
              < Scalar'Min (B (1).X, Scalar'Min (B (2).X, B (3).X))
           or else Scalar'Max (B (1).X, Scalar'Max (B (2).X, B (3).X)) + Tol
              < Scalar'Min (A (1).X, Scalar'Min (A (2).X, A (3).X))
           or else Scalar'Max (A (1).Y, Scalar'Max (A (2).Y, A (3).Y)) + Tol
              < Scalar'Min (B (1).Y, Scalar'Min (B (2).Y, B (3).Y))
           or else Scalar'Max (B (1).Y, Scalar'Max (B (2).Y, B (3).Y)) + Tol
              < Scalar'Min (A (1).Y, Scalar'Min (A (2).Y, A (3).Y))
           or else Scalar'Max (A (1).Z, Scalar'Max (A (2).Z, A (3).Z)) + Tol
              < Scalar'Min (B (1).Z, Scalar'Min (B (2).Z, B (3).Z))
           or else Scalar'Max (B (1).Z, Scalar'Max (B (2).Z, B (3).Z)) + Tol
              < Scalar'Min (A (1).Z, Scalar'Min (A (2).Z, A (3).Z))
         then
            return False;
         end if;
         NA := Normal (M, I); NB := Normal (M, J);
         NA := NA * (1.0 / Length (NA)); NB := NB * (1.0 / Length (NB));
         if Length (Cross (NA, NB)) < 1.0e-10
           and then abs Dot (NA, B (1) - A (1)) <= Tol
         then
            if abs NA.Y > abs NA.X then
               Drop := 2;
            end if;
            if abs NA.Z > Scalar'Max (abs NA.X, abs NA.Y) then
               Drop := 3;
            end if;
            for K in 1 .. 3 loop
               if Strict_Inside (A (K), B) or else Strict_Inside (B (K), A) then
                  return True;
               end if;
               for L in 1 .. 3 loop
                  declare
                     AN : constant Positive := (if K = 3 then 1 else K + 1);
                     BN : constant Positive := (if L = 3 then 1 else L + 1);
                     X : constant Scalar := Orient (A (K), A (AN), B (L));
                     Y : constant Scalar := Orient (A (K), A (AN), B (BN));
                     Z : constant Scalar := Orient (B (L), B (BN), A (K));
                     W : constant Scalar := Orient (B (L), B (BN), A (AN));
                     Bound : constant Scalar := Tol * Scalar'Max
                       (Length (A (AN) - A (K)), Length (B (BN) - B (L)));
                  begin
                     if ((X > Bound and then Y < -Bound) or else
                           (Y > Bound and then X < -Bound))
                       and then ((Z > Bound and then W < -Bound) or else
                                   (W > Bound and then Z < -Bound))
                     then
                        return True;
                     end if;
                  end;
               end loop;
            end loop;
            return Strict_Inside ((A (1) + A (2) + A (3)) * (1.0 / 3.0), B)
              or else Strict_Inside ((B (1) + B (2) + B (3)) * (1.0 / 3.0), A);
         end if;
         for K in 1 .. 3 loop
            if Segment_Hit (A (K), A ((if K = 3 then 1 else K + 1)), B)
              or else Segment_Hit (B (K), B ((if K = 3 then 1 else K + 1)), A)
            then
               return True;
            end if;
         end loop;
         return False;
      end Crossing;

      function Inside (P : Vec3; Shell : Natural) return Boolean is
         --  Solid-angle winding avoids ray/vertex tie-breaking.
         package Math is new Ada.Numerics.Generic_Elementary_Functions (Scalar);
         Sum : Scalar := 0.0;
         A, B, C : Vec3;
         LA, LB, LC, Num, Den : Scalar;
      begin
         for I in 1 .. M.NT loop
            if Component (I) = Shell then
               A := M.V (M.T (I).A) - P; B := M.V (M.T (I).B) - P;
               C := M.V (M.T (I).C) - P;
               LA := Length (A); LB := Length (B); LC := Length (C);
               Num := Dot (A, Cross (B, C));
               Den := LA * LB * LC + Dot (A, B) * LC + Dot (B, C) * LA + Dot (C, A) * LB;
               if Num /= 0.0 or else Den /= 0.0 then
                  Sum := Sum + 2.0 * Math.Arctan (Num, Den);
               end if;
            end if;
         end loop;
         return abs Sum > 6.0;
      end Inside;
   begin
      Result := Valid; Shells := 0;
      if M.NT = 0 then
         Result := Empty; return;
      end if;
      if M.NT > Max_Triangles then
         Result := Capacity_Exceeded; return;
      end if;
      for V in 1 .. M.NV loop
         if not Numeric.Valid (M.V (V)) then
            Result := Invalid_Coordinate; return;
         end if;
      end loop;
      for I in 1 .. M.NT loop
         if Length (Normal (M, I)) <= Tol * Tol then
            Result := Degenerate_Face; return;
         end if;
      end loop;
      if not Is_Watertight (M) then
         Result := Open_Boundary; return;
      end if;
      --  Follow the oriented incident-face ring at every used vertex.
      for V in 1 .. M.NV loop
         declare
            Start, Current, Next_Face : Triangle_Index := 0;
            Degree, Visited : Natural := 0;
            Next_Vertex : Vertex_Index := 0;
         begin
            for I in 1 .. M.NT loop
               for K in 1 .. 3 loop
                  if Corner (I, K) = V then
                     Degree := Degree + 1; Start := I;
                  end if;
               end loop;
            end loop;
            Current := Start;
            while Current /= 0 loop
               Visited := Visited + 1;
               if Visited > Degree then
                  Result := Non_Manifold_Vertex; return;
               end if;
               for K in 1 .. 3 loop
                  if Corner (Current, K) = V then
                     Next_Vertex := Corner (Current, (if K = 3 then 1 else K + 1));
                  end if;
               end loop;
               Next_Face := 0;
               for I in 1 .. M.NT loop
                  for K in 1 .. 3 loop
                     if Corner (I, K) = Next_Vertex
                       and then Corner (I, (if K = 3 then 1 else K + 1)) = V
                     then
                        Next_Face := I;
                     end if;
                  end loop;
               end loop;
               Current := Next_Face;
               exit when Current = Start;
            end loop;
            if Visited /= Degree then
               Result := Non_Manifold_Vertex; return;
            end if;
         end;
      end loop;
      for I in 1 .. M.NT loop
         for J in I + 1 .. M.NT loop
            if Shared (I, J) = 3 or else Crossing (I, J) then
               Result := Self_Intersection; return;
            end if;
         end loop;
      end loop;
      --  Identify shells by edge adjacency and compute signed component volume.
      for I in 1 .. M.NT loop
         if Component (I) = 0 then
            Shells := Shells + 1;
            First := 1; Last := 1; Queue (1) := I; Component (I) := Shells;
            Samples (Triangle_Index (Shells)) := M.T (I).A;
            while First <= Last loop
               declare
                  F : constant Triangle_Index := Queue (First);
               begin
                  Signed_Volume (Triangle_Index (Shells)) :=
                    Signed_Volume (Triangle_Index (Shells))
                    + Dot (M.V (M.T (F).A), Cross (M.V (M.T (F).B), M.V (M.T (F).C))) / 6.0;
                  for J in 1 .. M.NT loop
                     if Component (J) = 0 and then Shared (F, J) = 2 then
                        Last := Last + 1; Queue (Last) := J; Component (J) := Shells;
                     end if;
                  end loop;
               end;
               First := First + 1;
            end loop;
         end if;
      end loop;
      for I in 1 .. Shells loop
         declare
            Depth : Natural := 0;
         begin
            for J in 1 .. Shells loop
               if I /= J and then Inside (M.V (Samples (Triangle_Index (I))), J) then
                  Depth := Depth + 1;
               end if;
            end loop;
            if abs Signed_Volume (Triangle_Index (I)) <= Tol ** 3
              or else (Signed_Volume (Triangle_Index (I)) > 0.0) /= (Depth rem 2 = 0)
            then
               Result := Incorrect_Shell_Orientation; return;
            end if;
         end;
      end loop;
   end Check;
end Forge.Validation;
