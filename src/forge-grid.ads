--  Checked production coordinate arithmetic, in 2^-48 mm integer ticks.
with Interfaces;
package Forge.Grid with SPARK_Mode is
   use type Interfaces.Integer_64;
   Unit : constant := 2 ** 48;
   Limit : constant := 10_000 * Unit;
   subtype Tick is Interfaces.Integer_64 range -Limit .. Limit;
   type Wide is range -(2 ** 127) .. 2 ** 127 - 1;
   for Wide'Size use 128;
   type Point is record
      X, Y, Z : Tick := 0;
   end record;
   function To_Tick (V : Scalar) return Tick
     with Pre => V in -10_000.0 .. 10_000.0,
          Post => Scalar (To_Tick'Result) * Quantum = V;
   function To_Scalar (V : Tick) return Scalar
     with Post => To_Scalar'Result in -10_000.0 .. 10_000.0
            and then To_Tick (To_Scalar'Result) = V;
   --  Exact conversion between stored coordinates and integer ticks.
   procedure Translate (P : in out Point; By : Point; Ok : out Boolean)
     with Post => (if Ok then
                      P.X = P'Old.X + By.X and then P.Y = P'Old.Y + By.Y
                      and then P.Z = P'Old.Z + By.Z
                   else P = P'Old);
   --  Checked translation; failed arithmetic never modifies the point.
   function Norm_Squared (P : Point) return Wide is
     (Wide (P.X) * Wide (P.X) + Wide (P.Y) * Wide (P.Y) + Wide (P.Z) * Wide (P.Z));
   --  Exact squared distance from the origin, with widened products.
   function Quarter_Turn (P : Point; About : Axis) return Point is
     (case About is when X => (P.X, -P.Z, P.Y),
                    when Y => (P.Z, P.Y, -P.X), when Z => (-P.Y, P.X, P.Z))
     with Post => Norm_Squared (Quarter_Turn'Result) = Norm_Squared (P);
   --  Exact positive quarter turn about each coordinate axis.
   function Rounded (N : Wide) return Wide
     with Pre => N in -(Wide (Limit) * Wide (Limit)) .. Wide (Limit) * Wide (Limit),
          Post => Rounded'Result in
            -(Wide (Limit) * Wide (Limit) / Unit + 1)
            .. Wide (Limit) * Wide (Limit) / Unit + 1
            and then abs (N - Rounded'Result * Unit) <= Unit / 2
            and then (if abs (N - Rounded'Result * Unit) = Unit / 2
                      then Rounded'Result rem 2 = 0);
   --  Divide a product by Unit, nearest with ties to even.
   procedure Scale (V : in out Tick; Factor : Tick; Ok : out Boolean)
     with Pre => Factor > 0,
          Post => (if Ok then Wide (V) = Rounded (Wide (V'Old) * Wide (Factor))
                   else V = V'Old);
   --  Checked fixed-point scaling, with one rounding after the wide product.
end Forge.Grid;
