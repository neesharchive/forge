--  Bounded indexed triangle meshes. Well_Formed checks live distinct indices.
--  Is_Watertight checks reverse-edge pairing; Is_Solid also requires four faces.
--  These are structural/topological predicates, not full geometric validation.
--  Forge.Validation additionally checks vertex fans, embedding and shell nesting.
--  SPARK coverage is recorded in docs/VERIFICATION.md.

package Forge.Mesh with SPARK_Mode is

   type Vertex_Index   is range 0 .. 2 ** 24;
   type Triangle_Index is range 0 .. 2 ** 24;
   --  0 is "none"; live indices are 1 .. Count.

   type Triangle is record
      A, B, C : Vertex_Index := 0;
   end record;

   type Vertex_Array   is array (Vertex_Index range <>) of Vec3;
   type Triangle_Array is array (Triangle_Index range <>) of Triangle;

   type Tri_Mesh (Cap_V : Vertex_Index; Cap_T : Triangle_Index) is record
      NV : Vertex_Index   := 0;
      NT : Triangle_Index := 0;
      V  : Vertex_Array (1 .. Cap_V);
      T  : Triangle_Array (1 .. Cap_T);
   end record;

   function Well_Formed (M : Tri_Mesh) return Boolean is
     (M.NV <= M.Cap_V and then M.NT <= M.Cap_T
      and then (for all I in 1 .. M.NT =>
                  M.T (I).A in 1 .. M.NV
                  and then M.T (I).B in 1 .. M.NV
                  and then M.T (I).C in 1 .. M.NV
                  and then M.T (I).A /= M.T (I).B
                  and then M.T (I).B /= M.T (I).C
                  and then M.T (I).A /= M.T (I).C));
   --  Every triangle refers to live, distinct vertices. Precondition of
   --  everything below; postcondition of everything that builds a mesh.

   procedure Clear (M : in out Tri_Mesh)
     with Post => M.NV = 0 and then M.NT = 0 and then Well_Formed (M);

   procedure Add_Vertex (M : in out Tri_Mesh; P : Vec3; Index : out Vertex_Index; Ok : out Boolean)
     with Pre  => Well_Formed (M),
          Post => Well_Formed (M)
                  and then (if Ok then M.NV = M.NV'Old + 1 and then Index = M.NV
                            else M.NV = M.NV'Old and then Index = 0);

   procedure Add_Triangle (M : in out Tri_Mesh; A, B, C : Vertex_Index; Ok : out Boolean)
     with Pre  => Well_Formed (M)
                  and then A in 1 .. M.NV and then B in 1 .. M.NV and then C in 1 .. M.NV
                  and then A /= B and then B /= C and then A /= C,
          Post => Well_Formed (M) and then M.NV = M.NV'Old
                  and then (if Ok then M.NT = M.NT'Old + 1 else M.NT = M.NT'Old);

   procedure Copy (From : Tri_Mesh; To : out Tri_Mesh; Ok : out Boolean)
     with Pre  => Well_Formed (From),
          Post => Well_Formed (To)
                  and then (if Ok then To.NV = From.NV and then To.NT = From.NT);
   --  Ok = False when To's capacity is too small; To is then empty.

   ---------------------------------------------------------------------
   --  Topology
   ---------------------------------------------------------------------

   function Is_Watertight (M : Tri_Mesh) return Boolean
     with Pre => Well_Formed (M);
   --  Every directed edge (a, b) of every triangle has exactly one
   --  triangle containing the reverse edge (b, a), and no triangle
   --  contains (a, b) twice. That single condition gives closed and
   --  consistently paired at edges. Sort-based O(NT log NT).
   --  Vertex manifoldness and geometric embedding are checked by Forge.Validation.

   function Is_Solid (M : Tri_Mesh) return Boolean is
     (M.NT >= 4 and then Is_Watertight (M))
     with Pre => Well_Formed (M);

   ---------------------------------------------------------------------
   --  Measures
   ---------------------------------------------------------------------

   function Volume (M : Tri_Mesh) return Scalar
     with Pre => Well_Formed (M);
   --  Signed. Positive for an outward-oriented solid. Sum over
   --  triangles of dot (a, cross (b, c)) / 6.

   function Normal (M : Tri_Mesh; I : Triangle_Index) return Vec3
     with Pre => Well_Formed (M) and then I in 1 .. M.NT;
   --  Unnormalized face normal, cross (b - a, c - a).

   procedure Bounds (M : Tri_Mesh; Lo, Hi : out Vec3)
     with Pre => Well_Formed (M);
   --  Axis-aligned bounding box. Lo = Hi = Origin for an empty mesh.

end Forge.Mesh;
