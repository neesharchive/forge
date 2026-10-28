package body Forge.Fixed_Geometry with SPARK_Mode => Off is
   --  The prototype is tested independently. It is not the production BSP backend.
   type Wide is range -(2 ** 127) .. 2 ** 127 - 1;
   for Wide'Size use 128;

   function Determinant (A, B, C, P : Fixed.Point) return Wide;
   function Rounded (N, D : Wide) return Wide;

   function Determinant (A, B, C, P : Fixed.Point) return Wide is
      AX : constant Wide := Wide (B.X) - Wide (A.X);
      AY : constant Wide := Wide (B.Y) - Wide (A.Y);
      AZ : constant Wide := Wide (B.Z) - Wide (A.Z);
      BX : constant Wide := Wide (C.X) - Wide (A.X);
      BY : constant Wide := Wide (C.Y) - Wide (A.Y);
      BZ : constant Wide := Wide (C.Z) - Wide (A.Z);
      PX : constant Wide := Wide (P.X) - Wide (A.X);
      PY : constant Wide := Wide (P.Y) - Wide (A.Y);
      PZ : constant Wide := Wide (P.Z) - Wide (A.Z);
   begin
      return (AY * BZ - AZ * BY) * PX + (AZ * BX - AX * BZ) * PY
        + (AX * BY - AY * BX) * PZ;
   end Determinant;

   function Classify (A, B, C, P : Fixed.Point) return Side is
      D : constant Wide := Determinant (A, B, C, P);
   begin
      return (if D < 0 then Behind elsif D > 0 then In_Front else On_Plane);
   end Classify;

   function Rounded (N, D : Wide) return Wide is
      Q : Wide := N / D;
      R : constant Wide := abs (N rem D);
   begin
      if R > D / 2 or else (D rem 2 = 0 and then R = D / 2 and then Q rem 2 /= 0) then
         Q := Q + (if N < 0 then -1 else 1);
      end if;
      return Q;
   end Rounded;

   procedure Parse_Decimal (Text : String; Value : out Fixed.Tick; Ok : out Boolean) is
      Negative, Dot : Boolean := False;
      Num : Wide := 0;
      Den : Wide := 1;
      Digits_After, Digits_Total : Natural := 0;
      N : Wide;
   begin
      Ok := False; Value := 0;
      if Text'Length = 0 or else Text'Length > 16 then
         return;
      end if;
      for I in Text'Range loop
         if I = Text'First and then Text (I) in '-' | '+' then
            Negative := Text (I) = '-';
         elsif Text (I) = '.' and then not Dot then
            Dot := True;
         elsif Text (I) in '0' .. '9' then
            Digits_Total := Digits_Total + 1;
            Num := Num * 10 + Wide (Character'Pos (Text (I)) - Character'Pos ('0'));
            if Dot then
               Digits_After := Digits_After + 1; Den := Den * 10;
            end if;
         else
            return;
         end if;
      end loop;
      if Digits_Total = 0 or else Digits_After > 9 or else Num > 10_000 * Den then
         return;
      end if;
      N := Rounded (Num * 65_536, Den);
      if Negative then
         N := -N;
      end if;
      if N in Wide (Fixed.Tick'First) .. Wide (Fixed.Tick'Last) then
         Value := Fixed.Tick (N); Ok := True;
      end if;
   end Parse_Decimal;

   procedure Split_Edge (A, B, C, P, Q : Fixed.Point;
                         Intersection : out Fixed.Point; Ok : out Boolean)
   is
      DP : Wide := Determinant (A, B, C, P);
      DQ : Wide := Determinant (A, B, C, Q);
      Den : Wide;
      function Coordinate (X, Y : Fixed.Tick) return Fixed.Tick;
      function Coordinate (X, Y : Fixed.Tick) return Fixed.Tick is
      begin
         return Fixed.Tick (Rounded (Wide (X) * Den + (Wide (Y) - Wide (X)) * DP, Den));
      end Coordinate;
   begin
      Ok := False; Intersection := (others => 0);
      if DP = 0 then
         Intersection := P; Ok := True; return;
      elsif DQ = 0 then
         Intersection := Q; Ok := True; return;
      elsif (DP < 0) = (DQ < 0) then
         return;
      end if;
      if DP < DQ then
         DP := -DP; DQ := -DQ;
      end if;
      Den := DP - DQ;
      Intersection := (Coordinate (P.X, Q.X), Coordinate (P.Y, Q.Y), Coordinate (P.Z, Q.Z));
      Ok := Classify (A, B, C, Intersection) = On_Plane;
      if not Ok then
         Intersection := (others => 0);
      end if;
   end Split_Edge;
end Forge.Fixed_Geometry;
