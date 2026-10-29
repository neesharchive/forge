with Interfaces;

package body Forge.STL with SPARK_Mode => Off is
   --  Legacy binary32 file fields are encoded using integer arithmetic only.

   use type Interfaces.Unsigned_32;
   type Wide is range -(2 ** 127) .. 2 ** 127 - 1;
   for Wide'Size use 128;
   function To_Bits (V : Scalar) return Interfaces.Unsigned_32;
   function To_Bits (V : Scalar) return Interfaces.Unsigned_32 is
      Whole : constant Scalar := Truncated (V);
      T : constant Wide := abs Wide (Whole) * 2 ** 48
        + Wide (abs (V - Whole) / Scalar'Small);
      N : Wide := T;
      Power : Natural := 0;
      Mantissa, Divisor, Remainder : Wide;
      Exponent : Integer;
      Sign : constant Interfaces.Unsigned_32 := (if V < 0.0 then 16#8000_0000# else 0);
   begin
      if T = 0 then
         return 0;
      end if;
      while N >= 2 loop
         N := N / 2; Power := Power + 1;
      end loop;
      Exponent := Integer (Power) - 48 + 127;
      if Power <= 23 then
         Mantissa := T * 2 ** (23 - Power);
      else
         Divisor := 2 ** (Power - 23);
         Mantissa := T / Divisor; Remainder := T rem Divisor;
         if Remainder > Divisor / 2 or else
           (Remainder = Divisor / 2 and then Mantissa rem 2 /= 0)
         then
            Mantissa := Mantissa + 1;
         end if;
      end if;
      if Mantissa = 2 ** 24 then
         Mantissa := Mantissa / 2; Exponent := Exponent + 1;
      end if;
      return Sign or Interfaces.Unsigned_32 (Exponent) * 2 ** 23
        or Interfaces.Unsigned_32 (Mantissa - 2 ** 23);
   end To_Bits;

   procedure Write (M : Tri_Mesh; Buffer : out Byte_Array; Last : out Natural) is
      P : Positive := Buffer'First;

      procedure U32 (V : Interfaces.Unsigned_32);
      procedure F32 (V : Scalar);
      procedure Vec (V : Vec3);

      procedure U32 (V : Interfaces.Unsigned_32) is
         X : Interfaces.Unsigned_32 := V;
      begin
         for I in 1 .. 4 loop
            Buffer (P) := Byte (X and 16#FF#);
            X := X / 256;
            P := P + 1;
         end loop;
      end U32;

      procedure F32 (V : Scalar) is
      begin
         U32 (To_Bits (V));
      end F32;

      procedure Vec (V : Vec3) is
      begin
         F32 (V.X); F32 (V.Y); F32 (V.Z);
      end Vec;

      Header : constant String := "forge binary STL";
   begin
      Buffer := [others => 0];
      for I in Header'Range loop
         Buffer (P + I - 1) := Byte (Character'Pos (Header (I)));
      end loop;
      P := Buffer'First + 80;
      U32 (Interfaces.Unsigned_32 (M.NT));
      for I in 1 .. M.NT loop
         Vec (Normal (M, I));
         Vec (M.V (M.T (I).A));
         Vec (M.V (M.T (I).B));
         Vec (M.V (M.T (I).C));
         Buffer (P) := 0; Buffer (P + 1) := 0;
         P := P + 2;
      end loop;
      Last := P - 1;
   end Write;

end Forge.STL;
