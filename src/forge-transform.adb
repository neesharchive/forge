with Forge.Grid;
package body Forge.Transform with SPARK_Mode => Off is
   --  Fixed-point range reduction and elementary functions live in Forge.

   procedure Translate (M : in out Tri_Mesh; By : Vec3) is
      Delta_P : constant Grid.Point :=
        (Grid.To_Tick (By.X), Grid.To_Tick (By.Y), Grid.To_Tick (By.Z));
      P : Grid.Point;
      Ok : Boolean;
   begin
      for I in 1 .. M.NV loop
         P := (Grid.To_Tick (M.V (I).X), Grid.To_Tick (M.V (I).Y), Grid.To_Tick (M.V (I).Z));
         Grid.Translate (P, Delta_P, Ok);
         if not Ok then
            raise Constraint_Error with "translation outside coordinate domain";
         end if;
         M.V (I) := (Grid.To_Scalar (P.X), Grid.To_Scalar (P.Y), Grid.To_Scalar (P.Z));
      end loop;
   end Translate;

   procedure Scale (M : in out Tri_Mesh; F : Scalar) is
      Factor : constant Grid.Tick := Grid.To_Tick (F);
      PX, PY, PZ : Grid.Tick;
      GX, GY, GZ : Boolean;
   begin
      for I in 1 .. M.NV loop
         PX := Grid.To_Tick (M.V (I).X); PY := Grid.To_Tick (M.V (I).Y);
         PZ := Grid.To_Tick (M.V (I).Z);
         Grid.Scale (PX, Factor, GX); Grid.Scale (PY, Factor, GY); Grid.Scale (PZ, Factor, GZ);
         if not (GX and GY and GZ) then
            raise Constraint_Error with "scale outside coordinate domain";
         end if;
         M.V (I) := (Grid.To_Scalar (PX), Grid.To_Scalar (PY), Grid.To_Scalar (PZ));
      end loop;
   end Scale;

   procedure Rotate (M : in out Tri_Mesh; About : Axis; Degrees : Scalar) is
      C, S : Scalar;
      Turns : constant Integer := Integer (Degrees / 90.0);
      P : Grid.Point;
   begin
      if Degrees = Scalar (Turns) * 90.0 then
         for I in 1 .. M.NV loop
            P := (Grid.To_Tick (M.V (I).X), Grid.To_Tick (M.V (I).Y),
                  Grid.To_Tick (M.V (I).Z));
            for J in 1 .. Turns mod 4 loop
               P := Grid.Quarter_Turn (P, About);
            end loop;
            M.V (I) := (Grid.To_Scalar (P.X), Grid.To_Scalar (P.Y), Grid.To_Scalar (P.Z));
         end loop;
         return;
      end if;
      Sin_Cos (Degrees, S, C);
      for I in 1 .. M.NV loop
         declare
            P : constant Vec3 := M.V (I);
         begin
            case About is
               when X => M.V (I) := (P.X, C * P.Y - S * P.Z, S * P.Y + C * P.Z);
               when Y => M.V (I) := (C * P.X + S * P.Z, P.Y, -S * P.X + C * P.Z);
               when Z => M.V (I) := (C * P.X - S * P.Y, S * P.X + C * P.Y, P.Z);
            end case;
         end;
      end loop;
   end Rotate;

end Forge.Transform;
