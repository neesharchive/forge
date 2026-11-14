--  Boolean operations on solids. THE PROJECT.
--
--  Given two solids A and B, produce a solid that is their union,
--  difference (A minus B) or intersection.
--
--  Method: BSP-tree CSG (csg.js) in whole grid steps (Forge.Exact), then
--  a repair into an indexed mesh: weld, T-joints, clean, fan, check.
--  See "CSG: the project" in ARCHITECTURE.md.
--
--  No heap: the caller hands in a Workspace (Size_For gives a start;
--  retry bigger on Workspace_Full) and a Validity.Workspace.
--
--  Contract: solid in, solid out, or Status /= Success with a reason
--  and an empty Result. Never a mesh that fails the solid check.

with Forge.Exact;
with Forge.Mesh;     use Forge.Mesh;
with Forge.Validity;

package Forge.CSG with SPARK_Mode is

   type Operation is (Union, Difference, Intersection);

   type Outcome is
     (Success,
      Empty_Result,      --  nothing is left (disjoint intersection, A inside B for A - B)
      Workspace_Full,    --  retry with a larger Workspace
      Result_Full,       --  the result needs more room than Result has
      Input_Not_Solid,   --  A or B fails the solid check
      Out_Of_Range,      --  a coordinate beyond the exact range (Exact.Max_Units steps)
      Result_Not_Solid); --  the result cannot be closed: see the reason

   Max_Reason : constant := 64;
   subtype Reason_String is String (1 .. Max_Reason);

   type Count is range 0 .. 2 ** 28;

   type Workspace (Max_Polygons, Max_Points, Max_Nodes : Count) is limited private;
   --  Room for the polygons the BSP creates, the points they hold (each
   --  split keeps the old polygon and adds two), and the tree nodes.

   procedure Size_For
     (Triangles : Triangle_Index; Factor : Positive; Polygons, Points, Nodes : out Count)
     with Post => Polygons > 0 and then Points > 0 and then Nodes > 0;
   --  A workspace size for inputs with this many triangles in total.
   --  Factor 1 is enough for primitives; multiply when Workspace_Full.

   procedure Apply
     (Op     : Operation;
      A, B   : Tri_Mesh;
      Result : in out Tri_Mesh;
      Work   : in out Workspace;
      Check  : in out Validity.Workspace;
      Status : out Outcome;
      Reason : out Reason_String;
      Last   : out Natural)
     with Pre  => Well_Formed (A) and then Well_Formed (B)
                  and then Validity.Fits (Check, A.NV, A.NT)
                  and then Validity.Fits (Check, B.NV, B.NT)
                  and then Validity.Fits (Check, Result.Cap_V, Result.Cap_T),
          Post => Well_Formed (Result)
                  and then Last <= Max_Reason
                  and then (if Status /= Success then Result.NT = 0);
   --  On Success, Result is a solid (Forge.Validity says Solid).
   --  Reason (1 .. Last) says what went wrong otherwise. Result must be
   --  a different object from A and B.

private

   --  A plane is a normal N (an exact cross product of two edges of an
   --  input triangle in the same face) and a point A on it. Pieces cut
   --  from a polygon keep its plane exactly.
   type Polygon is record
      N     : Exact.Vector;
      A     : Exact.Point;
      First : Count := 0;   --  its points are Pool (First .. First + Size - 1)
      Size  : Count := 0;
      Next  : Count := 0;   --  next polygon in the same list; 0 ends it
   end record;

   subtype Tree_Id is Natural range 0 .. 2;
   subtype Tree_Number is Tree_Id range 1 .. 2;

   type Node is record
      Has_Plane   : Boolean := False;
      N           : Exact.Vector;
      A           : Exact.Point;
      Front, Back : Count   := 0;   --  child nodes; 0 = none
      Head        : Count   := 0;   --  polygons lying in this node's plane
      Tree        : Tree_Id := 0;   --  1 = A's tree, 2 = B's
   end record;

   type Job is record
      At_Node, List : Count := 0;
   end record;

   type Point_Array   is array (Count range <>) of Exact.Point;
   type Polygon_Array is array (Count range <>) of Polygon;
   type Node_Array    is array (Count range <>) of Node;
   type Job_Array     is array (Count range <>) of Job;
   type Count_Array   is array (Count range <>) of Count;
   type Key_Array     is array (Count range <>) of Exact.Big;
   type Index_Array   is array (Count range <>) of Vertex_Index;

   type Box_Array  is array (Tree_Number) of Exact.Point;
   type Flag_Array is array (Tree_Number) of Boolean;
   type Root_Array is array (Tree_Number) of Count;

   type Workspace (Max_Polygons, Max_Points, Max_Nodes : Count) is limited record
      --  The BSP: polygons point into Pool, nodes hold lists of polygons.
      Pool     : Point_Array (1 .. Max_Points);
      Polys    : Polygon_Array (1 .. Max_Polygons);
      Nodes    : Node_Array (1 .. Max_Nodes);
      Jobs     : Job_Array (1 .. Max_Nodes);       --  explicit stack, no recursion
      Pool_N   : Count := 0;
      Polys_N  : Count := 0;
      Nodes_N  : Count := 0;
      Roots    : Root_Array := [others => 0];
      Lo, Hi   : Box_Array;                        --  each input's bounding box
      Inverted : Flag_Array := [others => False];  --  tree currently inside out
      --  The repair, one entry per point of an output polygon.
      Occ      : Count_Array (1 .. Max_Points);    --  pool slot of each point
      Perm     : Count_Array (1 .. Max_Points);    --  points sorted by key
      Parent   : Count_Array (1 .. Max_Points);    --  union-find for welding
      Root_Id  : Count_Array (1 .. Max_Points);    --  welded vertex of each root
      Loop_1   : Count_Array (1 .. Max_Points);    --  polygons as welded vertex loops
      Loop_2   : Count_Array (1 .. Max_Points);    --  the same, T-joints inserted
      Key      : Key_Array (1 .. Max_Points);
      --  Welded vertices.
      Pos      : Point_Array (1 .. Max_Points);
      By_Key   : Count_Array (1 .. Max_Points);    --  welded vertices sorted by key
      Key_W    : Key_Array (1 .. Max_Points);
      Remap    : Index_Array (1 .. Max_Points);    --  welded vertex -> Result vertex
      --  Output polygons.
      Out_P    : Count_Array (1 .. Max_Polygons);
      Start_1  : Count_Array (1 .. Max_Polygons);
      Len_1    : Count_Array (1 .. Max_Polygons);
      Start_2  : Count_Array (1 .. Max_Polygons);
      Len_2    : Count_Array (1 .. Max_Polygons);
   end record;

end Forge.CSG;
