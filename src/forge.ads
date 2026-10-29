--  forge: solid modeling with verified document and numeric helpers.
--
--  Root package: scalars, vectors, names. Pure. No I/O anywhere below
--  Forge.Session; the kernel computes, the session owns memory, the
--  front ends (cli/, ui/) talk to the session in lines of text.

with Bedrock.Names;

package Forge with SPARK_Mode, Pure is

   --  Fixed binary millimetres. Wide storage also accommodates measures and
   --  intermediate products; public coordinate bounds remain +/-10,000 mm.
   type Scalar is delta 2.0 ** (-48) range -(2.0 ** 63) .. 2.0 ** 63 - 1.0;
   for Scalar'Small use 2.0 ** (-48);
   for Scalar'Size use 128;
   Quantum : constant Scalar := 16#0.000000000001#;

   type Vec3 is record
      X, Y, Z : Scalar := 0.0;
   end record;
   Origin : constant Vec3 := (0.0, 0.0, 0.0);
   type Axis is (X, Y, Z);

   function "+" (A, B : Vec3) return Vec3 is ((A.X + B.X, A.Y + B.Y, A.Z + B.Z));
   function "-" (A, B : Vec3) return Vec3 is ((A.X - B.X, A.Y - B.Y, A.Z - B.Z));
   function "-" (A : Vec3) return Vec3 is ((-A.X, -A.Y, -A.Z));
   function "*" (A : Vec3; S : Scalar) return Vec3 is ((A.X * S, A.Y * S, A.Z * S));
   function "/" (A : Vec3; S : Scalar) return Vec3 is ((A.X / S, A.Y / S, A.Z / S));
   function Dot (A, B : Vec3) return Scalar is
     (Scalar'(A.X * B.X) + Scalar'(A.Y * B.Y) + Scalar'(A.Z * B.Z));
   function Cross (A, B : Vec3) return Vec3 is
     ((Scalar'(A.Y * B.Z) - Scalar'(A.Z * B.Y),
       Scalar'(A.Z * B.X) - Scalar'(A.X * B.Z),
       Scalar'(A.X * B.Y) - Scalar'(A.Y * B.X)));
   function Length (A : Vec3) return Scalar;
   function Normalized (A : Vec3) return Vec3;
   function Truncated (V : Scalar) return Scalar;
   --  Integral part, truncated toward zero using integer conversion.
   function Sqrt (V : Scalar) return Scalar;
   --  Nonnegative fixed-point square root; rejects negative arguments.
   procedure Sin_Cos (Degrees : Scalar; S, C : out Scalar);
   --  Fixed-point range reduction and Taylor evaluation; exact quarter turns.
   function Atan2 (Y, X : Scalar) return Scalar;
   --  Fixed-point signed angle in radians, in [-pi, pi].

   ---------------------------------------------------------------------
   --  Names: identifiers for solids in a session. Bedrock's bounded
   --  Name, so a name means the same thing in every GAP tool.
   ---------------------------------------------------------------------

   Max_Name : constant := Bedrock.Names.Max_Name;
   subtype Name is Bedrock.Names.Name;
   function To_Name (S : String) return Name renames Bedrock.Names.To_Name;
   function Image (N : Name) return String renames Bedrock.Names.Image;
   function "=" (A, B : Name) return Boolean renames Bedrock.Names."=";

end Forge;
