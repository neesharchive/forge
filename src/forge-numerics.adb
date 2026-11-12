package body Forge.Numerics is
   function Sin (Angle : Scalar) return Scalar is
      Turns : constant Long_Long_Integer := Long_Long_Integer (Angle / (2 * Pi));
      A : Scalar := Angle - Scalar (Turns) * (2 * Pi);
      Term, Sum : Scalar;
   begin
      if A > Pi then
         A := A - 2 * Pi;
      elsif A < -Pi then
         A := A + 2 * Pi;
      end if;
      if A > Pi / 2 then
         A := Pi - A;
      elsif A < -Pi / 2 then
         A := -Pi - A;
      end if;
      Term := A;
      Sum := A;
      for I in 1 .. 12 loop
         Term := -Scalar (Term * A) * A / ((2 * I) * (2 * I + 1));
         Sum := Sum + Term;
      end loop;
      return Sum;
   end Sin;

   function Cos (Angle : Scalar) return Scalar is
   begin
      return Sin (Angle + Pi / 2);
   end Cos;
end Forge.Numerics;
