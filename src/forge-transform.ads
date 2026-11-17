--  Rigid and scaling transforms. Vertices only; topology untouched.
--  Proof target M4: Well_Formed and Is_Solid are preserved, except that
--  a negative scale factor flips orientation (so Scale requires > 0).

with Forge.Mesh; use Forge.Mesh;

package Forge.Transform with SPARK_Mode is

   procedure Translate (M : in out Tri_Mesh; By : Vec3)
     with Pre  => Well_Formed (M),
          Post => Well_Formed (M) and then M.NV = M.NV'Old and then M.NT = M.NT'Old;

   procedure Scale (M : in out Tri_Mesh; F : Scalar)
     with Pre  => Well_Formed (M) and then F > 0.0,
          Post => Well_Formed (M) and then M.NV = M.NV'Old and then M.NT = M.NT'Old;

   procedure Scale_About
     (M : in out Tri_Mesh; Pivot : Vec3; Numerator, Denominator : Scalar)
     with Pre => Well_Formed (M) and then Numerator > 0.0 and then Denominator > 0.0,
          Post => Well_Formed (M) and then M.NV = M.NV'Old and then M.NT = M.NT'Old;
   --  Scale by Numerator / Denominator about Pivot. Only final world
   --  coordinates are range checked; the ratio is not quantized first.

   procedure Rotate (M : in out Tri_Mesh; About : Axis; Degrees : Scalar)
     with Pre  => Well_Formed (M),
          Post => Well_Formed (M) and then M.NV = M.NV'Old and then M.NT = M.NT'Old;
   --  Right-hand rule about the given axis through the origin.

end Forge.Transform;
