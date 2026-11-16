--  Document data shared with front ends. Forge.Session owns the tree,
--  executes Forge.Commands and maintains the only command history.
--  Names are stable handles while objects exist; World is reserved.

package Forge.Solid_Trees is

   Max_Solids : constant := 64;
   World : constant Name := To_Name ("world");
   type Node_Kind is
     (World_Node, Box_Node, Cylinder_Node, Sphere_Node,
      Union_Node, Difference_Node, Intersection_Node);

   type Node is record
      N        : Name;
      Parent   : Name := World;
      Order    : Natural := 0;
      Kind     : Node_Kind := World_Node;
      Size     : Vec3 := Origin;
      Position : Vec3 := Origin;
      Scale    : Scalar := 1.0;
   end record;
   --  Size: box extents, cylinder (radius, height, 0), sphere (radius, 0, 0).
   --  Position and scale describe world-space placement. Session updates
   --  descendants when transforming a group; meshes hold actual vertices,
   --  including any legacy rotations. Boolean meshes are not evaluated yet.
   --  Empty N marks a free slot. Parent links and Order define the tree.

   type Node_Array is array (Natural range <>) of Node;
   subtype Solid_Tree is Node_Array (0 .. Max_Solids);
   --  Slot 0 is World. Slot numbers are private implementation details;
   --  callers identify nodes by N and sort children by Order.

end Forge.Solid_Trees;
