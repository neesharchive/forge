with Ada.Strings.Fixed;
package body Forge.Text with SPARK_Mode => Off is
   type Wide is range -(2 ** 127) .. 2 ** 127 - 1;
   for Wide'Size use 128;
   Unit : constant Wide := 2 ** 48;

   function Number (V : Scalar) return String is
      Whole : constant Scalar := Truncated (V);
      Part : Wide := Wide (abs (V - Whole) / Scalar'Small);
      Buffer : String (1 .. 48);
      Last : Natural := 0;
      Prefix : constant String := Ada.Strings.Fixed.Trim
        (Wide'Image (abs Wide (Whole)), Ada.Strings.Both);
   begin
      while Part /= 0 loop
         Part := Part * 10;
         Last := Last + 1;
         Buffer (Last) := Character'Val (Character'Pos ('0') + Integer (Part / Unit));
         Part := Part rem Unit;
      end loop;
      return (if V < 0.0 then "-" else "") & Prefix
        & (if Last = 0 then "" else "." & Buffer (1 .. Last));
   end Number;

   procedure Parse (S : String; V : out Scalar; Ok : out Boolean) is
      type Decimal is array (1 .. 64) of Natural range 0 .. 9;
      Fraction : Decimal := [others => 0];
      Count : Natural := 0;
      Whole : Natural := 0;
      Bits : Wide := 0;
      Carry, Product : Natural;
      Negative, Dot, Seen, Nonzero : Boolean := False;
   begin
      Ok := False; V := 0.0;
      if S'Length = 0 then
         return;
      end if;
      for I in S'Range loop
         if I = S'First and then S (I) in '+' | '-' then
            Negative := S (I) = '-';
         elsif S (I) = '.' and then not Dot then
            Dot := True;
         elsif S (I) in '0' .. '9' then
            Seen := True;
            Product := Character'Pos (S (I)) - Character'Pos ('0');
            if Dot then
               if Count = 64 then
                  return;
               end if;
               Count := Count + 1; Fraction (Count) := Product;
               Nonzero := Nonzero or Product /= 0;
            else
               if Whole > 1_000 then
                  return;
               end if;
               Whole := Whole * 10 + Product;
               if Whole > 10_000 then
                  return;
               end if;
            end if;
         else
            return;
         end if;
      end loop;
      if not Seen or else (Whole = 10_000 and then Nonzero) then
         return;
      end if;
      --  Long division in base ten extracts 48 bits and a rounding bit.
      for Bit in 1 .. 49 loop
         Carry := 0;
         for J in reverse Fraction'Range loop
            Product := 2 * Fraction (J) + Carry;
            Fraction (J) := Product rem 10; Carry := Product / 10;
         end loop;
         if Bit <= 48 then
            Bits := Bits * 2 + Wide (Carry);
         elsif Carry = 1 and then
           (Bits rem 2 /= 0 or else (for some Digit of Fraction => Digit /= 0))
         then
            Bits := Bits + 1;
         end if;
      end loop;
      V := Scalar (Whole) + Scalar (Bits) * Scalar'Small;
      if Negative then
         V := -V;
      end if;
      Ok := True;
   end Parse;
end Forge.Text;
