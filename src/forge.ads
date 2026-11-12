--  forge: solid modeling with a proven topology kernel, driven by text.
--
--  Root package: scalars, vectors, names. Pure. No I/O anywhere below
--  Forge.Session; the kernel computes, the session owns memory, the
--  front ends (cli/, ui/) talk to the session in lines of text.

with Forge_Vectors;
with Bedrock.Names;

package Forge with SPARK_Mode, Pure is

   type Scalar is delta 2.0 ** (-32) range -(2.0 ** 80) .. 2.0 ** 80
     with Small => 2.0 ** (-32), Size => 128;
   --  Binary fixed point; the wider range accommodates products and volume.
   Coordinate_Limit : constant Scalar := 10_000.0;

   --  Fixed-point vector operations, re-exported so `use Forge` is enough.
   package Geometry is new Forge_Vectors (Scalar);

   subtype Vec3 is Geometry.Vector3;
   Origin : Vec3 renames Geometry.Zero3;

   function "=" (A, B : Vec3) return Boolean renames Geometry."=";
   function "+" (A, B : Vec3) return Vec3 renames Geometry."+";
   function "-" (A, B : Vec3) return Vec3 renames Geometry."-";
   function "-" (A : Vec3) return Vec3 renames Geometry."-";
   function "*" (A : Vec3; S : Scalar) return Vec3 renames Geometry."*";
   function Dot (A, B : Vec3) return Scalar renames Geometry.Dot;
   function Cross (A, B : Vec3) return Vec3 renames Geometry.Cross;
   function Length (A : Vec3) return Scalar;
   function Normalized (A : Vec3) return Vec3;

   subtype Axis is Geometry.Axis;
   function X return Axis renames Geometry.X;
   function Y return Axis renames Geometry.Y;
   function Z return Axis renames Geometry.Z;
   function "=" (A, B : Axis) return Boolean renames Geometry."=";

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
