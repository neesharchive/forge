with Forge.Numerics;

package body Forge.Transform with SPARK_Mode => Off is
   --  Candidate vertices are committed only after range and geometry checks.

   procedure Check_Point (P : Vec3);

   procedure Check_Point (P : Vec3) is
   begin
      if abs P.X > Coordinate_Limit or else abs P.Y > Coordinate_Limit
        or else abs P.Z > Coordinate_Limit
      then
         raise Constraint_Error with "coordinate outside modeling range";
      end if;
   end Check_Point;

   procedure Check_Faces (M : Tri_Mesh; Candidate : Vertex_Array);

   procedure Check_Faces (M : Tri_Mesh; Candidate : Vertex_Array) is
   begin
      for I in 1 .. M.NT loop
         declare
            A : constant Vec3 := Candidate (M.T (I).A);
            B : constant Vec3 := Candidate (M.T (I).B);
            C : constant Vec3 := Candidate (M.T (I).C);
         begin
            if Cross (B - A, C - A) = Origin then
               raise Constraint_Error with "transform collapses a face";
            end if;
         end;
      end loop;
   end Check_Faces;

   procedure Translate (M : in out Tri_Mesh; By : Vec3) is
      Candidate : Vertex_Array (1 .. M.NV);
   begin
      for I in 1 .. M.NV loop
         Candidate (I) := M.V (I) + By;
         Check_Point (Candidate (I));
      end loop;
      Check_Faces (M, Candidate);
      M.V (1 .. M.NV) := Candidate;
   end Translate;

   procedure Scale (M : in out Tri_Mesh; F : Scalar) is
      Candidate : Vertex_Array (1 .. M.NV);
   begin
      for I in 1 .. M.NV loop
         Candidate (I) := M.V (I) * F;
         Check_Point (Candidate (I));
      end loop;
      Check_Faces (M, Candidate);
      M.V (1 .. M.NV) := Candidate;
   end Scale;

   procedure Rotate (M : in out Tri_Mesh; About : Axis; Degrees : Scalar) is
      Candidate : Vertex_Array (1 .. M.NV);
      A : constant Scalar := Scalar (Degrees * Numerics.Pi) / 180;
      C : Scalar := Numerics.Cos (A);
      S : Scalar := Numerics.Sin (A);
      Quarter : constant Integer := Integer (Degrees / 90);
   begin
      if Degrees = Scalar (Quarter * 90) then
         case Quarter mod 4 is
            when 0 => C := 1.0; S := 0.0;
            when 1 => C := 0.0; S := 1.0;
            when 2 => C := -1.0; S := 0.0;
            when others => C := 0.0; S := -1.0;
         end case;
      end if;
      for I in 1 .. M.NV loop
         declare
            P : constant Vec3 := M.V (I);
         begin
            case About is
               when X => Candidate (I) := (P.X, C * P.Y - S * P.Z, S * P.Y + C * P.Z);
               when Y => Candidate (I) := (C * P.X + S * P.Z, P.Y, -S * P.X + C * P.Z);
               when Z => Candidate (I) := (C * P.X - S * P.Y, S * P.X + C * P.Y, P.Z);
            end case;
            Check_Point (Candidate (I));
         end;
      end loop;
      Check_Faces (M, Candidate);
      M.V (1 .. M.NV) := Candidate;
   end Rotate;

end Forge.Transform;
