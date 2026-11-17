with Ada.Unchecked_Conversion;
with Interfaces;

package body Forge.STL with SPARK_Mode => Off is
   --  Off for the float-to-bits conversion only.

   use type Interfaces.Unsigned_32;
   function To_Bits is new Ada.Unchecked_Conversion (Float, Interfaces.Unsigned_32);

   procedure U32 (Buffer : in out Byte_Array; P : in out Positive; V : Interfaces.Unsigned_32);
   procedure Vec (Buffer : in out Byte_Array; P : in out Positive; V : Vec3);

   procedure U32 (Buffer : in out Byte_Array; P : in out Positive; V : Interfaces.Unsigned_32) is
      X : Interfaces.Unsigned_32 := V;
   begin
      for I in 1 .. 4 loop
         Buffer (P) := Byte (X and 16#FF#);
         X := X / 256;
         P := P + 1;
      end loop;
   end U32;

   procedure Vec (Buffer : in out Byte_Array; P : in out Positive; V : Vec3) is
   begin
      U32 (Buffer, P, To_Bits (Float (V.X)));
      U32 (Buffer, P, To_Bits (Float (V.Y)));
      U32 (Buffer, P, To_Bits (Float (V.Z)));
   end Vec;

   procedure Write_Header (Triangle_Count : Natural; Buffer : out Byte_Array) is
      Header : constant String := "forge binary STL";
      P : Positive := Buffer'First + 80;
   begin
      Buffer := [others => 0];
      for I in Header'Range loop
         Buffer (Buffer'First + I - 1) := Byte (Character'Pos (Header (I)));
      end loop;
      U32 (Buffer, P, Interfaces.Unsigned_32 (Triangle_Count));
   end Write_Header;

   procedure Write_Triangle (M : Tri_Mesh; I : Triangle_Index; Buffer : out Byte_Array) is
      P : Positive := Buffer'First;
   begin
      Buffer := [others => 0];
      Vec (Buffer, P, Normal (M, I));
      Vec (Buffer, P, M.V (M.T (I).A));
      Vec (Buffer, P, M.V (M.T (I).B));
      Vec (Buffer, P, M.V (M.T (I).C));
   end Write_Triangle;

   procedure Write (M : Tri_Mesh; Buffer : out Byte_Array; Last : out Natural) is
      P : Positive := Buffer'First + 84;
   begin
      Buffer := [others => 0];
      Write_Header (Natural (M.NT), Buffer (Buffer'First .. Buffer'First + 83));
      for I in 1 .. M.NT loop
         Write_Triangle (M, I, Buffer (P .. P + 49));
         P := P + 50;
      end loop;
      Last := P - 1;
   end Write;

end Forge.STL;
