--  Exact geometry on the fixed-point grid.
--
--  A coordinate here is a whole number of 2**-32 mm steps (a Coord).
--  Normals are exact 128-bit cross products; a side test is about 142
--  bits, carried as a Wide (high, low) pair. So "which side" is the true
--  sign. The only rounding is in Crossing, where a new point is made,
--  and it is the same whichever polygon asks.
--
--  Exact within Max_Units steps of the origin (about 32.7 m).

package Forge.Exact with SPARK_Mode is

   type Big is range -(2 ** 127) .. 2 ** 127 - 1;

   Max_Units : constant := 2 ** 47;
   type Coord is range -Max_Units .. Max_Units;
   --  A coordinate as a count of grid steps.

   type Point is record
      X, Y, Z : Coord := 0;
   end record;

   type Vector is record
      X, Y, Z : Big := 0;
   end record;
   --  Differences of points, and plane normals (cross products).

   function Within (V : Vector; Limit : Big) return Boolean is
     (abs V.X <= Limit and then abs V.Y <= Limit and then abs V.Z <= Limit);
   function Max_Abs (V : Vector) return Big is
     (Big'Max (abs V.X, Big'Max (abs V.Y, abs V.Z)));
   function L1 (V : Vector) return Big is (abs V.X + abs V.Y + abs V.Z)
     with Pre => Within (V, 2 ** 120);
   function Is_Zero (V : Vector) return Boolean is (V.X = 0 and then V.Y = 0 and then V.Z = 0);

   ---------------------------------------------------------------------
   --  Between Scalar and steps. Exact both ways.
   ---------------------------------------------------------------------

   function Steps (S : Scalar) return Big;
   function To_Scalar (S : Big) return Scalar
     with Pre => abs S <= 2 ** 80;
   function Fits (V : Vec3) return Boolean;
   --  Every coordinate within Max_Units steps.
   function To_Point (V : Vec3) return Point
     with Pre => Fits (V);
   function To_Vec3 (P : Point) return Vec3;

   ---------------------------------------------------------------------
   --  Exact integer vectors
   ---------------------------------------------------------------------

   function "-" (A, B : Point) return Vector is
     (Big (A.X) - Big (B.X), Big (A.Y) - Big (B.Y), Big (A.Z) - Big (B.Z));
   function As_Vector (P : Point) return Vector is (Big (P.X), Big (P.Y), Big (P.Z));

   function Cross (A, B : Vector) return Vector
     with Pre => Within (A, 2 ** 48) and then Within (B, 2 ** 48);

   function Inner (A, B : Vector) return Big is (A.X * B.X + A.Y * B.Y + A.Z * B.Z)
     with Pre => Within (A, 2 ** 48) and then Within (B, 2 ** 48);
   --  The dot product of two differences of points: below 2**98, exact.

   function Before (A, B : Point) return Boolean is
     (A.X < B.X or else (A.X = B.X and then (A.Y < B.Y or else (A.Y = B.Y and then A.Z < B.Z))));
   --  A fixed order on points, so an edge always has a "first" end.

   type Wide is private;
   --  An integer of up to about 190 bits.

   Zero : constant Wide;

   function Dot (N, D : Vector) return Wide
     with Pre => Within (N, 2 ** 98) and then Within (D, 2 ** 48);
   --  N a normal (a cross product of edges), D a difference of points.
   function "+" (A, B : Wide) return Wide;
   function "-" (A, B : Wide) return Wide;
   function "-" (A : Wide) return Wide;
   function To_Wide (I : Big) return Wide
     with Pre => abs I < 2 ** 126;
   function Sign (W : Wide) return Integer
     with Post => Sign'Result in -1 .. 1;
   function High (W : Wide) return Big;
   --  W / 2**64, rounded down.

   ---------------------------------------------------------------------
   --  The two questions a boolean asks
   ---------------------------------------------------------------------

   function Side (N : Vector; A, P : Point; Tolerance : Big) return Integer
     with Pre  => Within (N, 2 ** 98) and then Tolerance in 0 .. 2 ** 120,
          Post => Side'Result in -1 .. 1;
   --  Point P against the plane through A with normal N: +1 in front
   --  (the side N points to), -1 behind, 0 on it, where "on" means
   --  |Dot (N, P - A)| <= Tolerance. Tolerance 0 is the exact test.

   function Crossing (N : Vector; A, From, To : Point) return Point
     with Pre => Within (N, 2 ** 98) and then Side (N, A, From, 0) * Side (N, A, To, 0) < 0;
   --  Where segment From-To crosses that plane, rounded to the nearest grid
   --  point. Crossing (N, A, From, To) = Crossing (N, A, To, From), bit for bit,
   --  so the two polygons sharing an edge make the same point.

private

   type Wide is record
      Hi : Big := 0;   --  value = Hi * 2**64 + Lo
      Lo : Big := 0;   --  0 <= Lo < 2**64
   end record;

   Zero : constant Wide := (Hi => 0, Lo => 0);

end Forge.Exact;
