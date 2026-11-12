--  Fixed-point elementary functions used by modeling.
package Forge.Numerics with Pure, SPARK_Mode => Off is
   Pi : constant Scalar := 13_493_037_704.0 / 4_294_967_296.0;
   function Sin (Angle : Scalar) return Scalar;
   function Cos (Angle : Scalar) return Scalar;
end Forge.Numerics;
