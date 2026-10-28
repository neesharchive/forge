--  Bounded fixed-grid prototype; not a claim of exact mesh constructions.
with Interfaces;
package Forge.Fixed with SPARK_Mode is
   use type Interfaces.Integer_64;
   subtype Tick is Interfaces.Integer_64 range -655_360_000 .. 655_360_000;
   Quantum : constant := 2.0 ** (-16);
   type Point is record
      X, Y, Z : Tick := 0;
   end record;
   function Quarter_Z (P : Point) return Point is ((-P.Y, P.X, P.Z));
   --  Exact permutation on the symmetric coordinate domain.
   procedure Translate (P : in out Point; By : Point; Ok : out Boolean)
     with Post => (if not Ok then P = P'Old);
   --  Translation commits only when each sum is representable.
   procedure Divide_Rounded (N : Interfaces.Integer_64; D : Positive;
                             Q : out Interfaces.Integer_64)
     with Pre => N > Interfaces.Integer_64'First,
          Post => Q >= Interfaces.Integer_64'Min (N, 0)
                  and then Q <= Interfaces.Integer_64'Max (N, 0);
   --  Nearest integer, ties to even; denominator is positive.
end Forge.Fixed;
