with Forge.Text;
package body Forge.Commands with SPARK_Mode => Off is
   --  Tokenization and decimal text boundaries are tested outside SPARK.

   Max_Tokens : constant := 10;
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
      N := 0; T := [others => <>];
      while I <= Line'Last loop
         while I <= Line'Last and then Line (I) in ' ' | ASCII.HT loop
            I := I + 1;
         end loop;
         exit when I > Line'Last;
         if N = Max_Tokens then
            N := Max_Tokens + 1; return;
         end if;
         N := N + 1;
         if Line (I) = '"' then
            I := I + 1; T (N).First := I;
            while I <= Line'Last and then Line (I) /= '"' loop
               I := I + 1;
            end loop;
            if I > Line'Last then
               N := Max_Tokens + 1; return;
            end if;
            T (N).Last := I - 1; I := I + 1;
            if I <= Line'Last and then Line (I) not in ' ' | ASCII.HT then
               N := Max_Tokens + 1; return;
            end if;
         else
            T (N).First := I;
            while I <= Line'Last and then Line (I) not in ' ' | ASCII.HT loop
               I := I + 1;
            end loop;
            T (N).Last := I - 1;
         end if;
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
      if S'Length > Max_Path then
         raise Constraint_Error;
      end if;
      P.Length := S'Length;
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
            Forge.Text.Parse (Tok (Tok_I), Nums (Into), G);
         end if;
      exception
         when Constraint_Error => G := False;
      end Get_Num;

      procedure Get_Name (Tok_I, Into : Positive) is
         S : constant String := (if G then Tok (Tok_I) else "");
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
         S : constant String := (if G then Lower (Tok (Tok_I)) else "");
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
         if not G then
            return;
         end if;
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
      if N > Max_Tokens then
         Fail ("too many tokens");
         return;
      end if;

      declare
         Verb : constant String := Lower (Tok (1));
      begin
         if Verb = "box" then
            Need (5); Get_Name (2, 1); Get_Num (3, 1); Get_Num (4, 2); Get_Num (5, 3);
            if G then
               G := Nums (1) > 0.0 and Nums (2) > 0.0 and Nums (3) > 0.0;
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
               G := Nums (1) > 0.0 and Nums (2) > 0.0;
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
         elsif Verb = "tree" or else Verb = "evaluate" or else Verb = "bounds" then
            Need (2); Get_Name (2, 1);
            if G then
               if Verb = "tree" then
                  C := (K => Tree, Target => Names (1));
               elsif Verb = "bounds" then
                  C := (K => Inspect_Bounds, Target => Names (1));
               else
                  C := (K => Evaluate, Target => Names (1));
               end if;
            end if;
         elsif Verb = "params" then
            Need (3); Get_Name (2, 1);
            if G then
               C := (K => Params, Param_Name => Names (1), Param_Path => To_Path (Tok (3)));
            end if;
         elsif Verb = "setbox" or else Verb = "setcylinder" or else Verb = "setop"
           or else Verb = "replace" or else Verb = "swap" or else Verb = "settransform"
         then
            declare
               subtype Edit_Kind is Kind range Set_Box .. Swap;
               EK : Edit_Kind := Swap;
               M : Natural range 0 .. 2 := 0;
            begin
               if Verb = "setbox" then
                  EK := Set_Box; Need (6);
               elsif Verb = "setcylinder" then
                  EK := Set_Cylinder; Need (6);
               elsif Verb = "setop" then
                  EK := Set_Op; Need (4);
               elsif Verb = "replace" then
                  EK := Replace_Tree; Need (4);
               elsif Verb = "settransform" then
                  EK := Set_Transform;
                  if N < 5 then
                     G := False;
                  elsif Lower (Tok (4)) = "translate" then
                     Need (7); M := 0;
                     Get_Num (5, 1); Get_Num (6, 2); Get_Num (7, 3);
                  elsif Lower (Tok (4)) = "rotate" then
                     Need (6); M := 1; Get_Axis (5); Get_Num (6, 1);
                  elsif Lower (Tok (4)) = "scale" then
                     Need (5); M := 2; Get_Num (5, 1);
                  else
                     G := False;
                  end if;
               else
                  Need (3);
               end if;
               Get_Name (2, 1);
               if EK = Set_Box or else EK = Set_Cylinder then
                  Get_Num (4, 1); Get_Num (5, 2);
                  if EK = Set_Box then
                     Get_Num (6, 3);
                  else
                     Get_Segments (6);
                  end if;
               elsif EK = Replace_Tree then
                  Get_Name (4, 2);
               elsif EK = Set_Op and then G then
                  if Lower (Tok (4)) = "union" then
                     M := 0;
                  elsif Lower (Tok (4)) = "difference" then
                     M := 1;
                  elsif Lower (Tok (4)) = "intersect" then
                     M := 2;
                  else
                     G := False;
                  end if;
               end if;
               if G then
                  C := (K => EK, Edit_Name => Names (1), Path => To_Path (Tok (3)),
                        Values => (Nums (1), Nums (2), Nums (3)), Extra => Scalar (Seg),
                        Mode => M, Edit_Axis => Ax, Source => Names (2));
               end if;
            end;
         elsif Verb = "info" then
            Need (2); Get_Name (2, 1);
            if G then
               C := (K => Info, Target => Names (1));
            end if;
         elsif Verb = "list" then
            Need (1);
            C := (K => List);
         elsif Verb = "redo" then
            Need (1);
            C := (K => Redo);
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
            if G then
               C := (K => Save, File => To_Path (Tok (2)));
            end if;
         elsif Verb = "load" then
            Need (2);
            if G then
               C := (K => Load, File => To_Path (Tok (2)));
            end if;
         else
            Fail ("unknown command: " & Tok (1));
            return;
         end if;

         if not G then
            Fail ("bad arguments for " & Verb);
         end if;
      end;
   exception
      when Constraint_Error => Fail ("argument out of range or path too long");
   end Parse;

   -----------
   -- Image --
   -----------

   function Img (S : Scalar) return String is (Forge.Text.Number (S));

   function Image (C : Command) return String is
      function Quoted (P : Path_String) return String;
      function Quoted (P : Path_String) return String is
         S : constant String := Image (P);
      begin
         if (for some Ch of S => Ch in ' ' | ASCII.HT) then
            return '"' & S & '"';
         end if;
         return S;
      end Quoted;
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
         when Set_Box | Set_Cylinder | Set_Transform | Set_Op | Replace_Tree | Swap =>
            declare
               Prefix : constant String :=
                 (case C.K is when Set_Box => "setbox", when Set_Cylinder => "setcylinder",
                  when Set_Transform => "settransform", when Set_Op => "setop",
                  when Replace_Tree => "replace", when others => "swap")
                 & " " & Image (C.Edit_Name) & " " & Image (C.Path);
            begin
               case C.K is
                  when Set_Box =>
                     return Prefix & " " & Img (C.Values.X) & " " & Img (C.Values.Y)
                       & " " & Img (C.Values.Z);
                  when Set_Cylinder =>
                     return Prefix & " " & Img (C.Values.X) & " " & Img (C.Values.Y)
                       & " " & Img (C.Extra);
                  when Set_Op =>
                     return Prefix & (case C.Mode is when 0 => " union",
                                      when 1 => " difference", when others => " intersect");
                  when Replace_Tree => return Prefix & " " & Image (C.Source);
                  when Set_Transform =>
                     if C.Mode = 0 then
                        return Prefix & " translate " & Img (C.Values.X) & " "
                          & Img (C.Values.Y) & " " & Img (C.Values.Z);
                     elsif C.Mode = 1 then
                        return Prefix & " rotate "
                          & (case C.Edit_Axis is when X => "x", when Y => "y", when Z => "z")
                          & " " & Img (C.Values.X);
                     else
                        return Prefix & " scale " & Img (C.Values.X);
                     end if;
                  when others => return Prefix;
               end case;
            end;
         when Tree => return "tree " & Image (C.Target);
         when Evaluate => return "evaluate " & Image (C.Target);
         when Inspect_Bounds => return "bounds " & Image (C.Target);
         when Params => return "params " & Image (C.Param_Name) & " " & Image (C.Param_Path);
         when Redo => return "redo";
         when Info =>
            return "info " & Image (C.Target);
         when List =>
            return "list";
         when Undo =>
            return "undo";
         when Export =>
            return "export " & Image (C.Ex_Name) & " " & Quoted (C.Ex_Path);
         when Save =>
            return "save " & Quoted (C.File);
         when Load =>
            return "load " & Quoted (C.File);
         when Comment =>
            return "#";
         when Empty =>
            return "";
      end case;
   end Image;

end Forge.Commands;
