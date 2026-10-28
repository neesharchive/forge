--  Geometric qualification beyond index and reverse-edge checks.
with Forge.Mesh;
package Forge.Validation with SPARK_Mode is
   type Status is (Valid, Empty, Invalid_Coordinate, Degenerate_Face,
                   Open_Boundary, Non_Manifold_Vertex, Self_Intersection,
                   Incorrect_Shell_Orientation, Capacity_Exceeded);
   Max_Triangles : constant := 20_000;
   procedure Check (M : Mesh.Tri_Mesh; Result : out Status; Shells : out Natural)
     with Pre => Mesh.Well_Formed (M),
          Post => Shells <= Natural (M.NT);
   --  Checks bounded meshes, including vertex fans, embedding and shell nesting.
end Forge.Validation;
