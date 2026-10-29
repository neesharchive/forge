package body Forge with SPARK_Mode => Off is
   type Wide is range -(2 ** 127) .. 2 ** 127 - 1;
   for Wide'Size use 128;
   Pi : constant Scalar := 884_279_719_003_556 * Scalar'Small;

   function Truncated (V : Scalar) return Scalar is
      R : Scalar := Scalar (Long_Long_Integer (V));
   begin
      if V > 0.0 and then R > V then
         R := R - 1.0;
      elsif V < 0.0 and then R < V then
         R := R + 1.0;
      end if;
      return R;
   end Truncated;

   function Sqrt (V : Scalar) return Scalar is
      R : Scalar := (if V > 1.0 then V else 1.0);
      Next : Scalar;
      N, Root, Next_Root : Wide;
   begin
      if V < 0.0 then
         raise Constraint_Error with "negative square root";
      elsif V = 0.0 then
         return 0.0;
      end if;
      --  Length normalizes its input before calling Sqrt. In this domain
      --  the scaled radicand fits 128 bits and integer Newton is exact.
      if V <= 4.0 then
         N := Wide (V / Quantum) * 2 ** 48;
         Root := 2 ** 49;
         for I in 1 .. 128 loop
            Next_Root := (Root + N / Root) / 2;
            if Next_Root >= Root then
               return Scalar (Root) * Quantum;
            end if;
            Root := Next_Root;
         end loop;
         raise Constraint_Error with "integer square root convergence";
      end if;
      for I in 1 .. 128 loop
         Next := R / 2.0 + Scalar'(V / R) / 2.0;
         if abs (Next - R) <= Scalar'Small then
            return Next;
         end if;
         R := Next;
      end loop;
      raise Constraint_Error with "square root convergence";
   end Sqrt;

   function Length (A : Vec3) return Scalar is
      M : constant Scalar := Scalar'Max (abs A.X, Scalar'Max (abs A.Y, abs A.Z));
      P : Vec3;
   begin
      if M = 0.0 then
         return 0.0;
      end if;
      P := (A.X / M, A.Y / M, A.Z / M);
      return M * Sqrt (Dot (P, P));
   end Length;

   function Normalized (A : Vec3) return Vec3 is
      L : constant Scalar := Length (A);
   begin
      if L = 0.0 then
         raise Constraint_Error with "zero normal";
      end if;
      return (A.X / L, A.Y / L, A.Z / L);
   end Normalized;

   procedure Sin_Cos (Degrees : Scalar; S, C : out Scalar) is
      D : Scalar := Degrees - Truncated (Degrees / 360.0) * 360.0;
      A, A2, ST, CT : Scalar;
      Flip : Boolean := False;
   begin
      if D < 0.0 then
         D := D + 360.0;
      end if;
      if D = 0.0 then
         S := 0.0; C := 1.0; return;
      elsif D = 90.0 then
         S := 1.0; C := 0.0; return;
      elsif D = 180.0 then
         S := 0.0; C := -1.0; return;
      elsif D = 270.0 then
         S := -1.0; C := 0.0; return;
      end if;
      if D > 180.0 then
         D := D - 360.0;
      end if;
      if D > 90.0 then
         D := 180.0 - D; Flip := True;
      elsif D < -90.0 then
         D := -180.0 - D; Flip := True;
      end if;
      A := Scalar'(D / 180.0) * Pi; A2 := A * A;
      ST := A; CT := 1.0; S := ST; C := CT;
      for I in 1 .. 16 loop
         ST := -Scalar'(ST * A2) / Scalar ((2 * I) * (2 * I + 1));
         CT := -Scalar'(CT * A2) / Scalar ((2 * I - 1) * (2 * I));
         S := S + ST; C := C + CT;
      end loop;
      if Flip then
         C := -C;
      end if;
   end Sin_Cos;

   function Atan2 (Y, X : Scalar) return Scalar is
      function Atan_Unit (V : Scalar) return Scalar;
      function Atan_Unit (V : Scalar) return Scalar is
         T : Scalar := V;
         Offset : Scalar := 0.0;
         Term, Sum, T2 : Scalar;
      begin
         if V > 116_590_752_822_205 * Scalar'Small then
            T := (V - 1.0) / (V + 1.0); Offset := Pi / 4.0;
         end if;
         T2 := T * T; Term := T; Sum := T;
         for I in 1 .. 24 loop
            Term := -(Term * T2);
            Sum := Sum + Term / Scalar (2 * I + 1);
         end loop;
         return Offset + Sum;
      end Atan_Unit;
      A : Scalar;
   begin
      if X = 0.0 and then Y = 0.0 then
         return 0.0;
      elsif abs X >= abs Y then
         A := Atan_Unit (abs Y / abs X);
      else
         A := Pi / 2.0 - Atan_Unit (abs X / abs Y);
      end if;
      if X < 0.0 then
         A := Pi - A;
      end if;
      return (if Y < 0.0 then -A else A);
   end Atan2;
end Forge;
