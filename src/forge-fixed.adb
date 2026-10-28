package body Forge.Fixed with SPARK_Mode is
   procedure Translate (P : in out Point; By : Point; Ok : out Boolean) is
      X : constant Interfaces.Integer_64 := P.X + By.X;
      Y : constant Interfaces.Integer_64 := P.Y + By.Y;
      Z : constant Interfaces.Integer_64 := P.Z + By.Z;
   begin
      Ok := X in Tick and then Y in Tick and then Z in Tick;
      if Ok then
         P := (X, Y, Z);
      end if;
   end Translate;

   procedure Divide_Rounded (N : Interfaces.Integer_64; D : Positive;
                             Q : out Interfaces.Integer_64) is
      Den : constant Interfaces.Integer_64 := Interfaces.Integer_64 (D);
      R : constant Interfaces.Integer_64 := abs (N rem Den);
   begin
      Q := N / Den;
      if R > Den / 2 or else
        (Den rem 2 = 0 and then R = Den / 2 and then Q rem 2 /= 0)
      then
         if N > 0 then
            Q := Q + 1;
         else
            Q := Q - 1;
         end if;
      end if;
   end Divide_Rounded;
end Forge.Fixed;
