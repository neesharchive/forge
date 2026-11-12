--  Fixed-point vector operations, with explicit product result types.
generic
   type Fixed is delta <>;
package Forge_Vectors with SPARK_Mode, Pure is

   type Vector2 is record
      X, Y : Fixed := 0.0;
   end record;

   type Vector3 is record
      X, Y, Z : Fixed := 0.0;
   end record;

   Zero2 : constant Vector2 := (0.0, 0.0);
   Zero3 : constant Vector3 := (0.0, 0.0, 0.0);

   function "+" (A, B : Vector2) return Vector2 is (A.X + B.X, A.Y + B.Y);
   function "-" (A, B : Vector2) return Vector2 is (A.X - B.X, A.Y - B.Y);
   function "-" (A : Vector2) return Vector2 is (-A.X, -A.Y);
   function "*" (A : Vector2; S : Fixed) return Vector2 is (A.X * S, A.Y * S);
   function "*" (A : Vector2; S : Integer) return Vector2 is (A.X * S, A.Y * S);
   function Dot (A, B : Vector2) return Fixed is
     (Fixed (A.X * B.X) + Fixed (A.Y * B.Y));

   function "+" (A, B : Vector3) return Vector3 is (A.X + B.X, A.Y + B.Y, A.Z + B.Z);
   function "-" (A, B : Vector3) return Vector3 is (A.X - B.X, A.Y - B.Y, A.Z - B.Z);
   function "-" (A : Vector3) return Vector3 is (-A.X, -A.Y, -A.Z);
   function "*" (A : Vector3; S : Fixed) return Vector3 is (A.X * S, A.Y * S, A.Z * S);
   function "*" (A : Vector3; S : Integer) return Vector3 is (A.X * S, A.Y * S, A.Z * S);
   function Dot (A, B : Vector3) return Fixed is
     (Fixed (A.X * B.X) + Fixed (A.Y * B.Y) + Fixed (A.Z * B.Z));
   function Cross (A, B : Vector3) return Vector3 is
     (Fixed (A.Y * B.Z) - Fixed (A.Z * B.Y),
      Fixed (A.Z * B.X) - Fixed (A.X * B.Z),
      Fixed (A.X * B.Y) - Fixed (A.Y * B.X));

   type Axis is (X, Y, Z);

end Forge_Vectors;
