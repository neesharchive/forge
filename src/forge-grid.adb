package body Forge.Grid with SPARK_Mode is
   function To_Tick (V : Scalar) return Tick is (Tick (V / Quantum));
   function To_Scalar (V : Tick) return Scalar is (Scalar (V) * Quantum);

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

   function Rounded (N : Wide) return Wide is
      Q : Wide := N / Unit;
      R : constant Wide := abs (N rem Unit);
   begin
      if R > Unit / 2 or else (R = Unit / 2 and then Q rem 2 /= 0) then
         Q := Q + (if N < 0 then -1 else 1);
      end if;
      return Q;
   end Rounded;

   procedure Scale (V : in out Tick; Factor : Tick; Ok : out Boolean) is
      Product : constant Wide := Wide (V) * Wide (Factor);
      Q : constant Wide := Rounded (Product);
   begin
      Ok := Q in Wide (Tick'First) .. Wide (Tick'Last);
      if Ok then
         V := Tick (Q);
      end if;
   end Scale;
end Forge.Grid;
