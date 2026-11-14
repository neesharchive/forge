--  Validity: is this mesh really a solid, and if not, what is wrong
--  with it. The fast, detailed counterpart of Forge.Mesh.Is_Solid.
--
--  Inspect gives Is_Watertight's answer in O(NT log NT), not O(NT**2),
--  and reports what Is_Solid cannot see:
--
--    shells      separate closed pieces (a box with a void inside is 2)
--    genus       through-holes (a box with a hole drilled through is 1)
--    open edges  half-edges with no partner: a crack or a hole
--    repeated    the same directed edge twice: overlapping or flipped
--    nonmanifold vertices where two cones meet at a point (a "bowtie"),
--                which pass the edge test but are not a solid
--    slivers     needle triangles, the usual debris of a boolean
--
--  No heap: the caller hands in a Workspace.

with Forge.Mesh; use Forge.Mesh;

package Forge.Validity with SPARK_Mode is

   type Edge_Count is range 0 .. 3 * 2 ** 24 + 1;
   --  Three directed edges per triangle, plus one for loop bounds.

   function Edges_For (T : Triangle_Index) return Edge_Count is (3 * Edge_Count (T));

   type Workspace (Cap_V : Vertex_Index; Cap_E : Edge_Count) is limited private;
   --  Scratch memory: Cap_V vertices, Cap_E directed edges. A workspace
   --  made with Cap_E => Edges_For (Cap_T) inspects any mesh that a
   --  Tri_Mesh (Cap_V, Cap_T) can hold.

   function Fits (W : Workspace; NV : Vertex_Index; NT : Triangle_Index) return Boolean is
     (NV <= W.Cap_V and then Edges_For (NT) <= W.Cap_E);

   type Report is record
      Triangles            : Triangle_Index := 0;
      Vertices             : Vertex_Index   := 0;  --  vertices used by a triangle
      Edges                : Edge_Count     := 0;  --  undirected
      Open_Edges           : Edge_Count     := 0;  --  directed edges with no reverse
      Repeated_Edges       : Edge_Count     := 0;  --  extra copies of a directed edge
      Nonmanifold_Vertices : Vertex_Index   := 0;
      Shells               : Triangle_Index := 0;  --  edge-connected pieces
      Euler                : Integer        := 0;  --  Vertices - Edges + Triangles
      Genus                : Integer        := 0;  --  holes; meaningful when Manifold
      Degenerate           : Triangle_Index := 0;  --  zero area
      Slivers              : Triangle_Index := 0;  --  height < longest edge / 1000
      Area                 : Scalar         := 0.0;
      Volume               : Scalar         := 0.0;
      Watertight           : Boolean        := False;
      Manifold             : Boolean        := False;
      Solid                : Boolean        := False;
   end record;

   procedure Inspect (M : Tri_Mesh; W : in out Workspace; R : out Report)
     with Pre  => Well_Formed (M) and then Fits (W, M.NV, M.NT),
          Post => R.Triangles = M.NT
                  and then R.Watertight = (R.Open_Edges = 0 and then R.Repeated_Edges = 0)
                  and then (if R.Manifold then R.Watertight)
                  and then R.Solid = (M.NT >= 4 and then R.Manifold and then R.Volume > 0.0);
   --  Watertight is exactly Forge.Mesh.Is_Watertight (M); the tests check
   --  the two agree. Manifold adds: every vertex has a single fan of
   --  triangles around it. Solid adds at least four triangles and a
   --  positive volume (outward-facing). Everything Forge.Session accepts
   --  as a solid passes Solid.

   function Problem (R : Report) return String;
   --  The first reason R is not a solid, in a few words ("3 open edges",
   --  "1 nonmanifold vertex", "inside out"), or "" when R.Solid.

private

   type Edge_Array is array (Edge_Count range <>) of Edge_Count;
   type Flag_Array is array (Edge_Count range <>) of Boolean;
   type Tally_Array is array (Vertex_Index range <>) of Edge_Count;

   type Workspace (Cap_V : Vertex_Index; Cap_E : Edge_Count) is limited record
      Order   : Edge_Array (1 .. Cap_E);   --  edge ids, sorted by (from, to)
      Twin    : Edge_Array (1 .. Cap_E);   --  the reverse edge of each edge, 0 if none
      Parent  : Edge_Array (1 .. Cap_E);   --  union-find over triangles (1 .. NT)
      Seen    : Flag_Array (1 .. Cap_E);   --  corner already walked
      Corners : Tally_Array (1 .. Cap_V);  --  triangle corners at each vertex
      Fans    : Tally_Array (1 .. Cap_V);  --  separate fans found at each vertex
   end record;

end Forge.Validity;
