--  Fixed-grid feasibility backend. Exact predicates, checked grid constructions.
with Forge.Fixed;
package Forge.Fixed_Geometry with SPARK_Mode is
   type Side is (Behind, On_Plane, In_Front);
   function Classify (A, B, C, P : Fixed.Point) return Side;
   --  Exact determinant sign for bounded integer tick coordinates.
   procedure Parse_Decimal (Text : String; Value : out Fixed.Tick; Ok : out Boolean);
   --  Decimal millimetres, up to nine fractional digits; nearest tick, ties-even.
   procedure Split_Edge (A, B, C, P, Q : Fixed.Point;
                         Intersection : out Fixed.Point; Ok : out Boolean);
   --  Quantized crossing accepted only when it remains exactly on the plane.
end Forge.Fixed_Geometry;
