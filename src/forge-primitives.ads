--  Primitive solids. Each builds a watertight, outward-oriented mesh
--  centred on the origin, or reports Ok = False when the mesh has no
--  room. Extrude of a polygon is the natural next primitive (milestone).

with Forge.Mesh; use Forge.Mesh;

package Forge.Primitives with SPARK_Mode is

   procedure Box (M : in out Tri_Mesh; W, H, D : Scalar; Ok : out Boolean)
     with Pre  => W > 0.0 and then H > 0.0 and then D > 0.0,
          Post => Well_Formed (M) and then (if Ok then M.NV = 8 and then M.NT = 12);
   --  Axis-aligned, extents W along X, H along Y, D along Z.

   Max_Segments : constant := 256;

   procedure Cylinder
     (M : in out Tri_Mesh; R, H : Scalar; Segments : Positive; Ok : out Boolean)
     with Pre  => R > 0.0 and then H > 0.0 and then Segments in 3 .. Max_Segments,
          Post => Well_Formed (M);
   --  Axis along Z. Two fans of Segments triangles for the caps, 2 per
   --  segment for the wall: NV = 2 * Segments + 2, NT = 4 * Segments.

   procedure Sphere (M : in out Tri_Mesh; R : Scalar; Ok : out Boolean)
     with Pre => R > 0.0, Post => Well_Formed (M);
   --  Origin-centred sphere with 16 longitudes and 8 latitude intervals.
   --  NV = 114, NT = 224; outward triangles and shared pole vertices.

end Forge.Primitives;
