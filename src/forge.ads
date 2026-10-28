--  forge: solid modeling with verified document and numeric helpers.
--
--  Root package: scalars, vectors, names. Pure. No I/O anywhere below
--  Forge.Session; the kernel computes, the session owns memory, the
--  front ends (cli/, ui/) talk to the session in lines of text.

with Bedrock.Generic_Vectors;
with Bedrock.Names;

package Forge with SPARK_Mode, Pure is

   type Scalar is new Long_Float;
   --  Production mesh coordinates. Forge.Fixed provides a separate grid prototype.
   --  Proof scope is recorded in docs/VERIFICATION.md; geometry is approximate.

   --  Vectors come from bedrock, the GAP foundation crate, instantiated
   --  at forge's precision. Re-exported so `use Forge` is enough.
   package Geometry is new Bedrock.Generic_Vectors (Scalar);

   subtype Vec3 is Geometry.Vector3;
   Origin : Vec3 renames Geometry.Zero3;

   function "=" (A, B : Vec3) return Boolean renames Geometry."=";
   function "+" (A, B : Vec3) return Vec3 renames Geometry."+";
   function "-" (A, B : Vec3) return Vec3 renames Geometry."-";
   function "-" (A : Vec3) return Vec3 renames Geometry."-";
   function "*" (A : Vec3; S : Scalar) return Vec3 renames Geometry."*";
   function Dot (A, B : Vec3) return Scalar renames Geometry.Dot;
   function Cross (A, B : Vec3) return Vec3 renames Geometry.Cross;
   function Length (A : Vec3) return Scalar renames Geometry.Length;
   function Normalized (A : Vec3) return Vec3 renames Geometry.Normalized;

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
