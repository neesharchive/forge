--  Wavefront OBJ encoding, independent of files and session allocation.
package Forge.OBJ with SPARK_Mode => Off is
   Max_Line : constant := 160;
   function Vertex_Line (P : Vec3) return String;
   --  Emits a vertex with enough significant decimal digits to round-trip.
   function Face_Line (A, B, C : Positive) return String;
   --  Emits a 1-based triangular face in the supplied winding.
end Forge.OBJ;
