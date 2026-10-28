--  Checked numerical policy. Geometry is qualified within this domain.
package Forge.Numeric with SPARK_Mode is
   Limit : constant Scalar := 10_000.0;
   Epsilon : constant Scalar := 1.0e-8;
   function Valid (V : Scalar) return Boolean is (V >= -Limit and then V <= Limit);
   function Valid (V : Vec3) return Boolean is
     (Valid (V.X) and then Valid (V.Y) and then Valid (V.Z));
   function Close (A, B : Vec3) return Boolean is
     (abs (A.X - B.X) <= Epsilon and then abs (A.Y - B.Y) <= Epsilon
      and then abs (A.Z - B.Z) <= Epsilon)
     with Pre => Valid (A) and then Valid (B);
end Forge.Numeric;
