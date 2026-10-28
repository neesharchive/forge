package body Forge.Model with SPARK_Mode is
   procedure Add (T : in out Tree; C : Commands.Command; L, R : Node_Id;
                  Id : out Node_Id; Ok : out Boolean) is
   begin
      Ok := T.Used < Max_Nodes;
      Id := 0;
      if Ok then
         T.Used := T.Used + 1;
         Id := T.Used;
         T.Nodes (Id) := (C, L, R);
      end if;
   end Add;

   procedure Clone (T : in out Tree; Root : Node_Id; Result : out Node_Id;
                    Ok : out Boolean)
   is
      Saved : constant Node_Id := T.Used;
      procedure Copy_Node (Id : Node_Id; New_Id : out Node_Id; Depth : Natural)
        with Post => T.Used >= T.Used'Old and then New_Id <= T.Used;

      procedure Copy_Node (Id : Node_Id; New_Id : out Node_Id; Depth : Natural) is
         L, R : Node_Id;
         Good : Boolean;
         Payload : Commands.Command;
      begin
         New_Id := 0;
         if Id = 0 then
            return;
         end if;
         if Id > Saved or else Depth > Max_Depth then
            Ok := False; return;
         end if;
         Copy_Node (T.Nodes (Id).Left, L, Depth + 1);
         if not Ok then
            return;
         end if;
         Copy_Node (T.Nodes (Id).Right, R, Depth + 1);
         if not Ok then
            return;
         end if;
         Payload := T.Nodes (Id).Payload;
         Add (T, Payload, L, R, New_Id, Good);
         Ok := Good;
      end Copy_Node;
   begin
      Ok := True;
      Copy_Node (Root, Result, 0);
      if not Ok then
         T.Used := Saved;
         Result := 0;
      end if;
   end Clone;

   function Valid_Subtree (T : Tree; Root : Node_Id) return Boolean is
      use type Commands.Kind;
      function Walk (Id : Node_Id; Depth : Natural) return Boolean
        with Subprogram_Variant => (Increases => Depth);
      function Walk (Id : Node_Id; Depth : Natural) return Boolean is
         C : Commands.Kind;
      begin
         if Id = 0 or else Id > T.Used or else Depth > Max_Depth then
            return False;
         end if;
         C := T.Nodes (Id).Payload.K;
         if C in Commands.Box | Commands.Cylinder then
            return T.Nodes (Id).Left = 0 and then T.Nodes (Id).Right = 0;
         elsif C in Commands.Translate | Commands.Rotate | Commands.Scale then
            return T.Nodes (Id).Right = 0 and then Walk (T.Nodes (Id).Left, Depth + 1);
         elsif C in Commands.Union | Commands.Difference | Commands.Intersect then
            return Walk (T.Nodes (Id).Left, Depth + 1)
              and then Walk (T.Nodes (Id).Right, Depth + 1);
         end if;
         return False;
      end Walk;
   begin
      return Walk (Root, 0);
   end Valid_Subtree;

   function Resolve (T : Tree; Root : Node_Id; Path : String) return Node_Id is
      Id : Node_Id := Root;
   begin
      if Path'Length = 0 then
         return 0;
      end if;
      if Path = "." then
         return (if Id <= T.Used then Id else 0);
      end if;
      if Path'Length > Max_Depth then
         return 0;
      end if;
      for C of Path loop
         if Id = 0 or else Id > T.Used then
            return 0;
         end if;
         case C is
            when 'L' =>
               if T.Nodes (Id).Right = 0 then
                  return 0;
               end if;
               Id := T.Nodes (Id).Left;
            when 'C' =>
               if T.Nodes (Id).Right /= 0 then
                  return 0;
               end if;
               Id := T.Nodes (Id).Left;
            when 'R' => Id := T.Nodes (Id).Right;
            when others => return 0;
         end case;
      end loop;
      return (if Id <= T.Used then Id else 0);
   end Resolve;
end Forge.Model;
