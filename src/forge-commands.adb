package body Forge.Commands with SPARK_Mode => Off is
   --  Off: text parsing and formatting are outside SPARK. The grammar is
   --  small enough that a hand-written SPARK tokenizer is a fair task.

   Max_Tokens : constant := 8;
   type Token_Bounds is record
      First, Last : Natural := 0;
   end record;
   type Token_Array is array (1 .. Max_Tokens) of Token_Bounds;

   procedure Tokenize (Line : String; T : out Token_Array; N : out Natural);
   function Lower (S : String) return String;
   function To_Path (S : String) return Path_String;
   function Img (S : Scalar) return String;

   procedure Tokenize (Line : String; T : out Token_Array; N : out Natural) is
      I : Natural := Line'First;
   begin
      N := 0;
      T := [others => <>];
      while I <= Line'Last loop
         while I <= Line'Last and then Line (I) = ' ' loop
            I := I + 1;
         end loop;
         exit when I > Line'Last;
         exit when N = Max_Tokens;
         N := N + 1;
         T (N).First := I;
         while I <= Line'Last and then Line (I) /= ' ' loop
            I := I + 1;
         end loop;
         T (N).Last := I - 1;
      end loop;
   end Tokenize;

   function Lower (S : String) return String is
      R : String := S;
   begin
      for I in R'Range loop
         if R (I) in 'A' .. 'Z' then
            R (I) := Character'Val (Character'Pos (R (I)) + 32);
         end if;
      end loop;
      return R;
   end Lower;

   function To_Path (S : String) return Path_String is
      P : Path_String;
   begin
      P.Length := Natural'Min (S'Length, Max_Path);
      P.Text (1 .. P.Length) := S (S'First .. S'First + P.Length - 1);
      return P;
   end To_Path;

   -----------
   -- Parse --
   -----------

   procedure Parse (Line : String; C : out Command; Ok : out Boolean; Error : out Path_String) is
      T : Token_Array;
      N : Natural;
      G : Boolean := True;  --  grammar ok so far

      --  Argument slots, filled by the helpers below, read by the
      --  aggregates. Splitting "parse" from "build" sidesteps the
      --  arbitrary-evaluation-order rule on in-out parameters.
      Names : array (1 .. 4) of Name;
      Nums  : array (1 .. 4) of Scalar := [others => 0.0];
      Ax    : Axis := Z;
      Seg   : Positive := 32;

      function Tok (I : Positive) return String is (Line (T (I).First .. T (I).Last));

      procedure Need (Count : Natural);
      procedure Get_Num (Tok_I, Into : Positive);
      procedure Get_Name (Tok_I, Into : Positive);
      procedure Get_Axis (Tok_I : Positive);
      procedure Get_Segments (Tok_I : Positive);
      procedure Fail (Msg : String);

      procedure Need (Count : Natural) is
      begin
         if N /= Count then
            G := False;
         end if;
      end Need;

      procedure Get_Num (Tok_I, Into : Positive) is
      begin
         if G then
            Nums (Into) := Scalar'Value (Tok (Tok_I));
            if abs Nums (Into) > Coordinate_Limit then
               G := False;
            end if;
         end if;
      exception
         when Constraint_Error => G := False;
      end Get_Num;

      procedure Get_Name (Tok_I, Into : Positive) is
         S : constant String := Tok (Tok_I);
      begin
         if not G then
            return;
         end if;
         if S'Length > Max_Name or else S'Length = 0 then
            G := False;
            return;
         end if;
         for Ch of S loop
            if not (Ch in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_') then
               G := False;
               return;
            end if;
         end loop;
         Names (Into) := To_Name (S);
      end Get_Name;

      procedure Get_Axis (Tok_I : Positive) is
         S : constant String := Lower (Tok (Tok_I));
      begin
         if S = "x" then
            Ax := X;
         elsif S = "y" then
            Ax := Y;
         elsif S = "z" then
            Ax := Z;
         else
            G := False;
         end if;
      end Get_Axis;

      procedure Get_Segments (Tok_I : Positive) is
         V : Integer;
      begin
         V := Integer'Value (Tok (Tok_I));
         if V in 3 .. 256 then
            Seg := V;
         else
            G := False;
         end if;
      exception
         when Constraint_Error => G := False;
      end Get_Segments;

      procedure Fail (Msg : String) is
      begin
         C := (K => Empty);
         Ok := False;
         Error := To_Path (Msg);
      end Fail;

   begin
      Ok := True;
      Error := To_Path ("");
      C := (K => Empty);
      Tokenize (Line, T, N);

      if N = 0 then
         return;
      end if;
      if Line (T (1).First) = '#' then
         C := (K => Comment);
         return;
      end if;

      declare
         Verb : constant String := Lower (Tok (1));
      begin
         if Verb = "box" then
            Need (5); Get_Name (2, 1); Get_Num (3, 1); Get_Num (4, 2); Get_Num (5, 3);
            if G then
               C := (K => Box, Box_Name => Names (1), W => Nums (1), H => Nums (2), D => Nums (3));
            end if;
         elsif Verb = "cylinder" then
            if N = 5 then
               Get_Segments (5);
            elsif N /= 4 then
               G := False;
            end if;
            Get_Name (2, 1); Get_Num (3, 1); Get_Num (4, 2);
            if G then
               C := (K => Cylinder, Cyl_Name => Names (1), R => Nums (1), CH => Nums (2),
                     Segments => Seg);
            end if;
         elsif Verb = "translate" then
            Need (5); Get_Name (2, 1); Get_Num (3, 1); Get_Num (4, 2); Get_Num (5, 3);
            if G then
               C := (K => Translate, Tr_Name => Names (1), By => (Nums (1), Nums (2), Nums (3)));
            end if;
         elsif Verb = "rotate" then
            Need (4); Get_Name (2, 1); Get_Axis (3); Get_Num (4, 1);
            if G then
               C := (K => Rotate, Rot_Name => Names (1), About => Ax, Degrees => Nums (1));
            end if;
         elsif Verb = "scale" then
            Need (3); Get_Name (2, 1); Get_Num (3, 1);
            if G then
               C := (K => Scale, Sc_Name => Names (1), Factor => Nums (1));
            end if;
         elsif Verb = "union" then
            Need (4); Get_Name (2, 1); Get_Name (3, 2); Get_Name (4, 3);
            if G then
               C := (K => Union, Result => Names (1), A => Names (2), B => Names (3));
            end if;
         elsif Verb = "difference" then
            Need (4); Get_Name (2, 1); Get_Name (3, 2); Get_Name (4, 3);
            if G then
               C := (K => Difference, Result => Names (1), A => Names (2), B => Names (3));
            end if;
         elsif Verb = "intersect" then
            Need (4); Get_Name (2, 1); Get_Name (3, 2); Get_Name (4, 3);
            if G then
               C := (K => Intersect, Result => Names (1), A => Names (2), B => Names (3));
            end if;
         elsif Verb = "copy" then
            Need (3); Get_Name (2, 1); Get_Name (3, 2);
            if G then
               C := (K => Copy, Cp_Name => Names (1), From => Names (2));
            end if;
         elsif Verb = "delete" then
            Need (2); Get_Name (2, 1);
            if G then
               C := (K => Delete, Target => Names (1));
            end if;
         elsif Verb = "info" then
            Need (2); Get_Name (2, 1);
            if G then
               C := (K => Info, Target => Names (1));
            end if;
         elsif Verb = "list" then
            Need (1);
            C := (K => List);
         elsif Verb = "undo" then
            Need (1);
            C := (K => Undo);
         elsif Verb = "export" then
            Need (3); Get_Name (2, 1);
            if G then
               C := (K => Export, Ex_Name => Names (1), Ex_Path => To_Path (Tok (3)));
            end if;
         elsif Verb = "save" then
            Need (2);
            C := (K => Save, File => To_Path (Tok (2)));
         elsif Verb = "load" then
            Need (2);
            C := (K => Load, File => To_Path (Tok (2)));
         else
            Fail ("unknown command: " & Tok (1));
            return;
         end if;

         if not G then
            Fail ("bad arguments for " & Verb);
         end if;
      end;
   end Parse;

   -----------
   -- Image --
   -----------

   function Img (S : Scalar) return String is
      type Wide_Integer is range -(2 ** 127) .. 2 ** 127 - 1;
      Magnitude : constant Scalar := abs S;
      Whole : constant Wide_Integer := Wide_Integer (Magnitude);
      Integral : constant Wide_Integer :=
        (if Scalar (Whole) > Magnitude then Whole - 1 else Whole);
      Fraction : Scalar := Magnitude - Scalar (Integral);
      Digits_Text : String (1 .. 32);
      Last : Natural := 0;
      Raw : constant String := Integral'Image;
   begin
      while Fraction /= 0.0 loop
         Fraction := Fraction * 10;
         declare
            Rounded : constant Integer := Integer (Fraction);
            Digit : constant Integer :=
              (if Scalar (Rounded) > Fraction then Rounded - 1 else Rounded);
         begin
            Last := Last + 1;
            Digits_Text (Last) := Character'Val (Character'Pos ('0') + Digit);
            Fraction := Fraction - Scalar (Digit);
         end;
      end loop;
      return (if S < 0.0 then "-" else "") & Raw (2 .. Raw'Last)
        & (if Last = 0 then "" else "." & Digits_Text (1 .. Last));
   end Img;

   function Image (C : Command) return String is
   begin
      case C.K is
         when Box =>
            return "box " & Image (C.Box_Name) & " " & Img (C.W) & " " & Img (C.H)
              & " " & Img (C.D);
         when Cylinder =>
            return "cylinder " & Image (C.Cyl_Name) & " " & Img (C.R) & " " & Img (C.CH)
              & Positive'Image (C.Segments);
         when Translate =>
            return "translate " & Image (C.Tr_Name) & " " & Img (C.By.X) & " " & Img (C.By.Y)
              & " " & Img (C.By.Z);
         when Rotate =>
            return "rotate " & Image (C.Rot_Name) & " "
              & (case C.About is when X => "x", when Y => "y", when Z => "z")
              & " " & Img (C.Degrees);
         when Scale =>
            return "scale " & Image (C.Sc_Name) & " " & Img (C.Factor);
         when Union =>
            return "union " & Image (C.Result) & " " & Image (C.A) & " " & Image (C.B);
         when Difference =>
            return "difference " & Image (C.Result) & " " & Image (C.A) & " " & Image (C.B);
         when Intersect =>
            return "intersect " & Image (C.Result) & " " & Image (C.A) & " " & Image (C.B);
         when Copy =>
            return "copy " & Image (C.Cp_Name) & " " & Image (C.From);
         when Delete =>
            return "delete " & Image (C.Target);
         when Info =>
            return "info " & Image (C.Target);
         when List =>
            return "list";
         when Undo =>
            return "undo";
         when Export =>
            return "export " & Image (C.Ex_Name) & " " & Image (C.Ex_Path);
         when Save =>
            return "save " & Image (C.File);
         when Load =>
            return "load " & Image (C.File);
         when Comment =>
            return "#";
         when Empty =>
            return "";
      end case;
   end Image;

end Forge.Commands;
