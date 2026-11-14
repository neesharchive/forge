--  Indexed triangle mesh: the one representation every operation reads
--  and writes. Bounded by discriminants, no heap in the kernel; the
--  session allocates meshes, the kernel only computes on them.
--
--  A solid is a mesh that is CLOSED (watertight) and CONSISTENTLY
--  ORIENTED (every triangle counter-clockwise seen from outside, so
--  every shared edge appears once in each direction). Is_Solid checks
--  both. Every operation in the kernel promises: solid in, solid out.
--
--  PROOF TARGET (the "proven geometry" of the project, v1 = topology)
--    M1  No index out of range anywhere (free with SPARK once the
--        Well_Formed predicate is a precondition).
--    M2  Is_Watertight is exactly "every directed edge has exactly one
--        reverse twin". State it as a ghost quantifier, prove the body.
--    M3  Primitives produce meshes with Is_Solid (box first).
--    M4  Transforms preserve Is_Solid (they touch vertices only; the
--        topology is untouched, so this is an equality proof on the
--        index arrays; note that a negative scale flips orientation).
--    M5  Volume of a solid is positive iff outward-oriented.

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
   --  consistently oriented at once. O(NT**2): this is the reference
   --  definition. Forge.Validity.Inspect computes the same answer in
   --  O(NT log NT) (and more); the session uses that one, and the tests
   --  check the two agree.

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
