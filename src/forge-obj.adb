with Ada.Text_IO;
with Ada.Strings.Fixed;
package body Forge.OBJ is
   function Number (V : Scalar) return String;
   function Number (V : Scalar) return String is
      package IO is new Ada.Text_IO.Float_IO (Scalar);
      Buffer : String (1 .. 48);
   begin
      IO.Put (Buffer, V, Aft => Scalar'Digits + 2, Exp => 4);
      return Ada.Strings.Fixed.Trim (Buffer, Ada.Strings.Both);
   end Number;

   function Vertex_Line (P : Vec3) return String is
   begin
      return "v " & Number (P.X) & " " & Number (P.Y) & " " & Number (P.Z);
   end Vertex_Line;

   function Face_Line (A, B, C : Positive) return String is
   begin
      return "f" & A'Image & B'Image & C'Image;
   end Face_Line;
end Forge.OBJ;
