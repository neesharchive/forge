package body Forge with SPARK_Mode => Off is
   function Length (A : Vec3) return Scalar is
      Squared : constant Scalar := Dot (A, A);
      Guess : Scalar := Scalar'Max (1.0, Squared);
      Next : Scalar;
   begin
      if Squared = 0.0 then
         return 0.0;
      end if;
      for I in 1 .. 256 loop
         Next := (Guess + Squared / Guess) / 2;
         if abs (Next - Guess) <= Scalar'Small then
            return Next;
         end if;
         Guess := Next;
      end loop;
      return Guess;
   end Length;

   function Normalized (A : Vec3) return Vec3 is
      L : constant Scalar := Length (A);
   begin
      return (A.X / L, A.Y / L, A.Z / L);
   end Normalized;
end Forge;
