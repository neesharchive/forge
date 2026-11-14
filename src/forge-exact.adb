package body Forge.Exact with SPARK_Mode => Off is
   --  Off: Steps divides one fixed-point value by another, which SPARK
   --  restricts. The integer bounds are noted inline.

   Base : constant Big := 2 ** 64;
   Step : constant Scalar := Scalar'Small;

   --  Rounds toward minus infinity (Ada's "/" rounds toward zero).
   function Floor_Div (X, M : Big) return Big is ((X - X mod M) / M);

   function Normalize (Hi, Lo : Big) return Wide is
     (Hi => Hi + Floor_Div (Lo, Base), Lo => Lo mod Base);

   function Bits (X : Big) return Natural;
   function Bit_Length (W : Wide) return Natural;
   function Shift_Down (W : Wide; S : Natural) return Big;

   function Steps (S : Scalar) return Big is (Big (S / Step));

   function To_Scalar (S : Big) return Scalar is (Scalar (Scalar (S) * Step));

   function Fits (V : Vec3) return Boolean is
     (abs Steps (V.X) <= Max_Units and then abs Steps (V.Y) <= Max_Units
      and then abs Steps (V.Z) <= Max_Units);

   function To_Point (V : Vec3) return Point is
     (Coord (Steps (V.X)), Coord (Steps (V.Y)), Coord (Steps (V.Z)));

   function To_Vec3 (P : Point) return Vec3 is
     (To_Scalar (Big (P.X)), To_Scalar (Big (P.Y)), To_Scalar (Big (P.Z)));

   --  Each product is below 2**96, so each component below 2**97.
   function Cross (A, B : Vector) return Vector is
     (A.Y * B.Z - A.Z * B.Y, A.Z * B.X - A.X * B.Z, A.X * B.Y - A.Y * B.X);

   ---------------------------------------------------------------------
   --  Wide: long multiplication in base 2**64
   ---------------------------------------------------------------------

   --  N up to 2**98, D up to 2**48. Each N component split into 64-bit
   --  halves: high * D < 2**82, low * D < 2**112, sums < 2**114.
   function Dot (N, D : Vector) return Wide is
      Hi : Big := 0;
      Lo : Big := 0;
      procedure Add (C, E : Big);
      procedure Add (C, E : Big) is
      begin
         Hi := Hi + Floor_Div (C, Base) * E;
         Lo := Lo + (C mod Base) * E;
      end Add;
   begin
      Add (N.X, D.X);
      Add (N.Y, D.Y);
      Add (N.Z, D.Z);
      return Normalize (Hi, Lo);
   end Dot;

   function "+" (A, B : Wide) return Wide is (Normalize (A.Hi + B.Hi, A.Lo + B.Lo));
   function "-" (A, B : Wide) return Wide is (Normalize (A.Hi - B.Hi, A.Lo - B.Lo));
   function "-" (A : Wide) return Wide is (Normalize (-A.Hi, -A.Lo));
   function To_Wide (I : Big) return Wide is (Normalize (0, I));
   function High (W : Wide) return Big is (W.Hi);

   --  Lo is never negative, so Hi decides the sign unless it is zero.
   function Sign (W : Wide) return Integer is
     (if W.Hi > 0 then 1 elsif W.Hi < 0 then -1 elsif W.Lo > 0 then 1 else 0);

   function Bits (X : Big) return Natural is
      Y : Big := X;
      N : Natural := 0;
   begin
      while Y > 0 loop
         Y := Y / 2;
         N := N + 1;
      end loop;
      return N;
   end Bits;

   --  Bit length of a positive Wide.
   function Bit_Length (W : Wide) return Natural is
     (if W.Hi > 0 then 64 + Bits (W.Hi) else Bits (W.Lo));

   --  W >= 0 divided by 2**S, rounded down. Needs Bit_Length (W) <= S + 62.
   function Shift_Down (W : Wide; S : Natural) return Big is
   begin
      if S = 0 then
         return W.Hi * Base + W.Lo;
      elsif S >= 64 then
         return W.Hi / Big'(2) ** (S - 64);
      else
         return W.Hi * Big'(2) ** (64 - S) + W.Lo / Big'(2) ** S;
      end if;
   end Shift_Down;

   ---------------------------------------------------------------------
   --  The two questions
   ---------------------------------------------------------------------

   function Side (N : Vector; A, P : Point; Tolerance : Big) return Integer is
      V : constant Wide := Dot (N, P - A);
   begin
      if Sign (V - To_Wide (Tolerance)) > 0 then
         return 1;
      elsif Sign (V + To_Wide (Tolerance)) < 0 then
         return -1;
      else
         return 0;
      end if;
   end Side;

   --  First + t (Last - First), t = Num / Den. Scaling both to 62 bits
   --  costs under 2**-12 of a step. First is always the lower end in
   --  Before's order, so both polygons on an edge get the same point.
   function Crossing (N : Vector; A, From, To : Point) return Point is
      First : constant Point := (if Before (To, From) then To else From);
      Last  : constant Point := (if Before (To, From) then From else To);
      S_F   : constant Wide := Dot (N, First - A);
      S_L   : constant Wide := Dot (N, Last - A);
      Num   : Wide := -S_F;
      Den   : Wide := S_L - S_F;
      Shift : Natural;
      T     : Big := 0;   --  t * 2**62

      --  F + round ((L - F) * t); (L - F) * T < 2**110.
      function Along (F, L : Coord) return Coord is
        (F + Coord (Floor_Div ((Big (L) - Big (F)) * T + 2 ** 61, 2 ** 62)));

   begin
      if Sign (Den) < 0 then
         Num := -Num;
         Den := -Den;
      end if;
      if Sign (Num) <= 0 then
         return First;
      elsif Sign (Num - Den) >= 0 then
         return Last;
      end if;
      Shift := Natural'Max (0, Bit_Length (Den) - 62);
      T := Shift_Down (Num, Shift) * 2 ** 62 / Shift_Down (Den, Shift);
      return (Along (First.X, Last.X), Along (First.Y, Last.Y), Along (First.Z, Last.Z));
   end Crossing;

end Forge.Exact;
