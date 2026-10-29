with Forge.Text;
package body Forge.OBJ is
   function Number (V : Scalar) return String renames Forge.Text.Number;

   function Vertex_Line (P : Vec3) return String is
   begin
      return "v " & Number (P.X) & " " & Number (P.Y) & " " & Number (P.Z);
   end Vertex_Line;

   function Face_Line (A, B, C : Positive) return String is
   begin
      return "f" & A'Image & B'Image & C'Image;
   end Face_Line;
end Forge.OBJ;
