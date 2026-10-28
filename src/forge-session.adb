with Ada.Strings.Fixed;
with Ada.Directories;
with Ada.Text_IO;
with Ada.Unchecked_Deallocation;
with GNAT.OS_Lib;
with Forge.CSG;
with Forge.Numeric;
with Forge.Model_Bounds;
with Forge.Primitives;
with Forge.OBJ;
with Forge.Transform;
with Forge.Validation;

package body Forge.Session is
   procedure Free_Mesh is new Ada.Unchecked_Deallocation (Tri_Mesh, Mesh_Access);
   procedure Free_State is new Ada.Unchecked_Deallocation (State, State_Access);
   type Scratch_Access is access CSG.Workspace;
   procedure Free_Scratch is new Ada.Unchecked_Deallocation (CSG.Workspace, Scratch_Access);
   procedure Set (R : out Response; Ok : Boolean; Msg : String) renames Responses.Set;
   procedure Append (R : in out Response; Msg : String) renames Responses.Append;
   Header : constant String := "# forge-format 1 numeric floating";

   procedure Dispose (D : in out State_Access);

   procedure Dispose (D : in out State_Access) is
   begin
      if D /= null then
         for Item of D.Solids loop
            Free_Mesh (Item.M);
         end loop;
         Free_State (D);
      end if;
   end Dispose;

   overriding procedure Finalize (S : in out Session) is
   begin
      Dispose (S.Data);
   end Finalize;

   function Find (D : State_Access; N : Name) return Natural;

   function Find (D : State_Access; N : Name) return Natural is
   begin
      if D /= null then
         for I in D.Solids'Range loop
            if D.Solids (I).Used and then D.Solids (I).N = N then
               return I;
            end if;
         end loop;
      end if;
      return 0;
   end Find;

   procedure Apply (D : in out State; C : Command; R : out Response);

   procedure Apply (D : in out State; C : Command; R : out Response) is
      Slot, IA, IB : Natural := 0;
      L, B, Root, Target : Model.Node_Id := 0;
      Good : Boolean := True;
      Payload : Command;

      function Need (N : Name) return Natural;

      function Need (N : Name) return Natural is
      begin
         for I in D.Solids'Range loop
            if D.Solids (I).Used and then D.Solids (I).N = N then
               return I;
            end if;
         end loop;
         Good := False;
         Set (R, False, "err no solid named " & Image (N));
         return 0;
      end Need;

      procedure Destination (N : Name);

      procedure Destination (N : Name) is
      begin
         for I in D.Solids'Range loop
            if D.Solids (I).Used and then D.Solids (I).N = N then
               Slot := I; return;
            end if;
         end loop;
         for I in D.Solids'Range loop
            if not D.Solids (I).Used then
               Slot := I; return;
            end if;
         end loop;
         Good := False;
         Set (R, False, "err capacity exceeded: named objects");
      end Destination;

      procedure Store (N : Name);

      procedure Store (N : Name) is
      begin
         if not Good then
            Set (R, False, "err capacity exceeded: expression nodes/depth");
         else
            D.Solids (Slot) := (Used => True, N => N, Root => Root, others => <>);
         end if;
      end Store;
   begin
      Set (R, True, "ok model updated; mesh not evaluated");
      case C.K is
         when Box | Cylinder =>
            if C.K = Box then
               if not Numeric.Valid (C.W) or else not Numeric.Valid (C.H)
                 or else not Numeric.Valid (C.D) or else C.W <= 0.0
                 or else C.H <= 0.0 or else C.D <= 0.0
               then
                  Set (R, False, "err invalid box dimensions"); return;
               end if;
               Destination (C.Box_Name);
            else
               if not Numeric.Valid (C.R) or else not Numeric.Valid (C.CH)
                 or else C.R <= 0.0 or else C.CH <= 0.0
               then
                  Set (R, False, "err invalid cylinder dimensions"); return;
               end if;
               Destination (C.Cyl_Name);
            end if;
            if Good then
               Model.Add (D.Tree, C, 0, 0, Root, Good);
               Store ((if C.K = Box then C.Box_Name else C.Cyl_Name));
            end if;
         when Translate | Rotate | Scale =>
            IA := Need ((case C.K is when Translate => C.Tr_Name,
                        when Rotate => C.Rot_Name, when others => C.Sc_Name));
            if not Good then
               return;
            end if;
            if (C.K = Translate and then not Numeric.Valid (C.By))
              or else (C.K = Rotate and then not Numeric.Valid (C.Degrees))
              or else (C.K = Scale and then
                         (not Numeric.Valid (C.Factor) or else C.Factor <= 0.0))
            then
               Set (R, False, "err transform outside supported numeric domain"); return;
            end if;
            Model.Add (D.Tree, C, D.Solids (IA).Root, 0, Root, Good);
            if Good then
               D.Solids (IA).Root := Root;
            else
               Set (R, False, "err capacity exceeded: expression nodes");
            end if;
         when Union | Difference | Intersect =>
            IA := Need (C.A);
            if not Good then
               return;
            end if;
            IB := Need (C.B);
            if not Good then
               return;
            end if;
            if C.Result = C.A or else C.Result = C.B then
               Set (R, False, "err result must differ from operand names"); return;
            end if;
            Destination (C.Result);
            if not Good then
               return;
            end if;
            Model.Clone (D.Tree, D.Solids (IA).Root, L, Good);
            if Good then
               Model.Clone (D.Tree, D.Solids (IB).Root, B, Good);
            end if;
            if Good then
               Model.Add (D.Tree, C, L, B, Root, Good);
            end if;
            Store (C.Result);
         when Copy =>
            IA := Need (C.From);
            if not Good then
               return;
            end if;
            Destination (C.Cp_Name);
            if Good then
               Model.Clone (D.Tree, D.Solids (IA).Root, Root, Good);
               Store (C.Cp_Name);
            end if;
         when Delete =>
            IA := Need (C.Target);
            if Good then
               D.Solids (IA).Used := False;
            end if;
         when Set_Box | Set_Cylinder | Set_Transform | Set_Op | Replace_Tree | Swap =>
            IA := Need (C.Edit_Name);
            if not Good then
               return;
            end if;
            Target := Model.Resolve (D.Tree, D.Solids (IA).Root, Image (C.Path));
            if Target = 0 then
               Set (R, False, "err invalid subtree path"); return;
            end if;
            Payload := D.Tree.Nodes (Target).Payload;
            case C.K is
               when Set_Box =>
                  if Payload.K /= Box or else not Numeric.Valid (C.Values)
                    or else C.Values.X <= 0.0 or else C.Values.Y <= 0.0 or else C.Values.Z <= 0.0
                  then
                     Set (R, False, "err expected box and positive dimensions"); return;
                  end if;
                  Payload.W := C.Values.X; Payload.H := C.Values.Y; Payload.D := C.Values.Z;
               when Set_Cylinder =>
                  if Payload.K /= Cylinder or else not Numeric.Valid (C.Values)
                    or else C.Values.X <= 0.0 or else C.Values.Y <= 0.0
                    or else C.Extra < 3.0 or else C.Extra > 256.0
                  then
                     Set (R, False, "err expected cylinder and valid dimensions"); return;
                  end if;
                  Payload.R := C.Values.X; Payload.CH := C.Values.Y;
                  Payload.Segments := Positive (C.Extra);
               when Set_Transform =>
                  if (C.Mode = 0 and then Payload.K /= Translate)
                    or else (C.Mode = 1 and then Payload.K /= Rotate)
                    or else (C.Mode = 2 and then Payload.K /= Scale)
                    or else not Numeric.Valid (C.Values)
                    or else (C.Mode = 2 and then C.Values.X <= 0.0)
                  then
                     Set (R, False, "err transform type or values invalid"); return;
                  end if;
                  case C.Mode is
                     when 0 => Payload.By := C.Values;
                     when 1 => Payload.About := C.Edit_Axis; Payload.Degrees := C.Values.X;
                     when 2 => Payload.Factor := C.Values.X;
                  end case;
               when Set_Op =>
                  if Payload.K not in Union | Difference | Intersect then
                     Set (R, False, "err expected Boolean node"); return;
                  end if;
                  declare
                     subtype Boolean_Kind is Kind range Union .. Intersect;
                     K : constant Boolean_Kind :=
                       (case C.Mode is when 0 => Union, when 1 => Difference,
                        when others => Intersect);
                  begin
                     Payload := (K => K, Result => Payload.Result, A => Payload.A, B => Payload.B);
                  end;
               when Replace_Tree =>
                  IB := Need (C.Source);
                  if not Good then
                     return;
                  end if;
                  Model.Clone (D.Tree, D.Solids (IB).Root, Root, Good);
                  if not Good then
                     Set (R, False, "err capacity exceeded: expression nodes"); return;
                  end if;
                  D.Tree.Nodes (Target) := D.Tree.Nodes (Root);
                  return;
               when Swap =>
                  if Payload.K not in Union | Difference | Intersect then
                     Set (R, False, "err expected Boolean node"); return;
                  end if;
                  L := D.Tree.Nodes (Target).Left;
                  D.Tree.Nodes (Target).Left := D.Tree.Nodes (Target).Right;
                  D.Tree.Nodes (Target).Right := L;
                  return;
               when others => null;
            end case;
            D.Tree.Nodes (Target).Payload := Payload;
         when others => Set (R, False, "err not a modeling command");
      end case;
   end Apply;

   procedure Rebuild (S : Session; Count : Natural; D : out State_Access; R : out Response);

   procedure Rebuild (S : Session; Count : Natural; D : out State_Access; R : out Response) is
   begin
      D := new State;
      Set (R, True, "ok");
      for I in 1 .. Count loop
         Apply (D.all, S.History (I), R);
         if not R.Ok then
            Dispose (D); return;
         end if;
      end loop;
   exception
      when others =>
         Dispose (D);
         raise;
   end Rebuild;

   procedure Evaluate_Node
     (D : State; Root : Model.Node_Id; M : in out Tri_Mesh;
      Scratch : in out Scratch_Access; R : out Response; Depth : Natural := 0);

   procedure Evaluate_Node
     (D : State; Root : Model.Node_Id; M : in out Tri_Mesh;
      Scratch : in out Scratch_Access; R : out Response; Depth : Natural := 0)
   is
      Good : Boolean := False;
      C : Command;
      L, B : Mesh_Access := null;
      Reason : CSG.Reason_String;
      Last : Natural;
   begin
      Clear (M);
      if Root = 0 or else Root > D.Tree.Used or else Depth > Model.Max_Depth then
         Set (R, False, "err expression depth or reference invalid"); return;
      end if;
      C := D.Tree.Nodes (Root).Payload;
      Set (R, True, "ok");
      case C.K is
         when Box => Primitives.Box (M, C.W, C.H, C.D, Good);
         when Cylinder => Primitives.Cylinder (M, C.R, C.CH, C.Segments, Good);
         when Translate | Rotate | Scale =>
            Evaluate_Node (D, D.Tree.Nodes (Root).Left, M, Scratch, R, Depth + 1);
            if not R.Ok then
               return;
            end if;
            case C.K is
               when Translate => Transform.Translate (M, C.By);
               when Rotate => Transform.Rotate (M, C.About, C.Degrees);
               when Scale => Transform.Scale (M, C.Factor);
               when others => null;
            end case;
            Good := True;
         when Union | Difference | Intersect =>
            L := new Tri_Mesh (M.Cap_V, M.Cap_T);
            B := new Tri_Mesh (M.Cap_V, M.Cap_T);
            Evaluate_Node (D, D.Tree.Nodes (Root).Left, L.all, Scratch, R, Depth + 1);
            if R.Ok then
               Evaluate_Node (D, D.Tree.Nodes (Root).Right, B.all, Scratch, R, Depth + 1);
            end if;
            if R.Ok then
               if Scratch = null then
                  Scratch := new CSG.Workspace;
               end if;
               CSG.Apply ((case C.K is when Union => CSG.Union,
                           when Difference => CSG.Difference, when others => CSG.Intersection),
                          L.all, B.all, M, Good, Reason, Last, Scratch.all);
               if not Good then
                  Set (R, False, "err " & Reason (1 .. Last));
               end if;
            end if;
            Free_Mesh (L); Free_Mesh (B);
            if not R.Ok then
               return;
            end if;
         when others => Set (R, False, "err invalid expression payload"); return;
      end case;
      if not Good then
         Set (R, False, "err capacity exceeded: mesh"); return;
      end if;
      for I in 1 .. M.NV loop
         if not Numeric.Valid (M.V (I)) then
            Clear (M); Set (R, False, "err coordinate outside supported domain"); return;
         end if;
      end loop;
      if M.NT /= 0 and then not Is_Solid (M) then
         Clear (M); Set (R, False, "err invalid evaluated mesh");
      end if;
   exception
      when others =>
         Free_Mesh (L); Free_Mesh (B);
         Clear (M);
         raise;
   end Evaluate_Node;

   procedure Evaluate_Solid (D : State_Access; I : Positive; R : out Response);

   procedure Evaluate_Solid (D : State_Access; I : Positive; R : out Response) is
      Scratch : Scratch_Access := null;
      Validity : Validation.Status;
      Shells : Natural;
      use type Validation.Status;
   begin
      if D.Solids (I).Status in Evaluated_Solid | Evaluated_Empty then
         Set (R, True, (if D.Solids (I).Status = Evaluated_Empty then "ok empty" else "ok solid"));
         return;
      end if;
      if D.Solids (I).M = null then
         D.Solids (I).M := new Tri_Mesh (Default_Cap_V, Default_Cap_T);
      end if;
      Evaluate_Node (D.all, D.Solids (I).Root, D.Solids (I).M.all, Scratch, R);
      Free_Scratch (Scratch);
      if R.Ok then
         Validation.Check (D.Solids (I).M.all, Validity, Shells);
         if Validity not in Validation.Valid | Validation.Empty then
            Set (R, False, "err invalid evaluated geometry: " & Validity'Image);
         end if;
      end if;
      if not R.Ok then
         D.Solids (I).Status := Failed;
         Clear (D.Solids (I).M.all);
      elsif D.Solids (I).M.NT = 0 then
         D.Solids (I).Status := Evaluated_Empty;
         Set (R, True, "ok empty");
      else
         D.Solids (I).Status := Evaluated_Solid;
         Set (R, True, "ok solid");
      end if;
   exception
      when Storage_Error | Constraint_Error =>
         Free_Scratch (Scratch);
         D.Solids (I).Status := Failed;
         if D.Solids (I).M /= null then
            Clear (D.Solids (I).M.all);
         end if;
         Set (R, False, "err capacity or numeric range exceeded during evaluation");
   end Evaluate_Solid;

   procedure Describe (D : State; Id : Model.Node_Id; R : in out Response;
                       Path : String := "."; Depth : Natural := 0);

   procedure Describe (D : State; Id : Model.Node_Id; R : in out Response;
                       Path : String := "."; Depth : Natural := 0) is
      C : Command;
   begin
      if not R.Ok then
         return;
      end if;
      if Id = 0 or else Depth > Model.Max_Depth then
         Append (R, " [invalid depth/reference]"); return;
      end if;
      C := D.Tree.Nodes (Id).Payload;
      declare
         Text : constant String := " [" & Path & " " & Image (C) & "]";
      begin
         if R.Length + Text'Length > Max_Response then
            Set (R, False, "err tree response capacity exceeded; inspect with params");
            return;
         end if;
         Append (R, Text);
      end;
      if D.Tree.Nodes (Id).Left /= 0 then
         Describe (D, D.Tree.Nodes (Id).Left, R,
                   (if Path = "." then "" else Path)
                   & (if D.Tree.Nodes (Id).Right = 0 then "C" else "L"), Depth + 1);
      end if;
      if D.Tree.Nodes (Id).Right /= 0 then
         Describe (D, D.Tree.Nodes (Id).Right, R,
                   (if Path = "." then "" else Path) & "R", Depth + 1);
      end if;
   end Describe;

   procedure Write_File (Path : String; Data : String; R : out Response);

   procedure Write_File (Path : String; Data : String; R : out Response) is
      F : Ada.Text_IO.File_Type;
      Temp : constant String := Path & ".forge-tmp";
      Good : Boolean;
   begin
      if Ada.Directories.Exists (Temp) then
         Set (R, False, "err temporary output already exists"); return;
      end if;
      Ada.Text_IO.Create (F, Ada.Text_IO.Out_File, Temp);
      Ada.Text_IO.Put (F, Data);
      Ada.Text_IO.Close (F);
      GNAT.OS_Lib.Rename_File (Temp, Path, Good);
      if not Good then
         Ada.Directories.Delete_File (Temp);
         Set (R, False, "err cannot replace " & Path);
      else
         Set (R, True, "ok saved " & Path);
      end if;
   exception
      when Ada.Text_IO.Name_Error | Ada.Text_IO.Use_Error | Ada.Text_IO.Device_Error =>
         if Ada.Text_IO.Is_Open (F) then
            Ada.Text_IO.Close (F);
         end if;
         if Ada.Directories.Exists (Temp) then
            Ada.Directories.Delete_File (Temp);
         end if;
         Set (R, False, "err cannot write " & Path);
   end Write_File;

   procedure Do_Export (D : State_Access; I : Positive; Path : String; R : out Response);

   procedure Do_Export (D : State_Access; I : Positive; Path : String; R : out Response) is
      F : Ada.Text_IO.File_Type;
      Temp : constant String := Path & ".forge-tmp";
      Good : Boolean;
   begin
      if Path'Length < 4 or else Path (Path'Last - 3 .. Path'Last) /= ".obj" then
         Set (R, False, "err export requires an .obj file"); return;
      end if;
      Evaluate_Solid (D, I, R);
      if not R.Ok then
         return;
      end if;
      if D.Solids (I).M.NT = 0 then
         Set (R, False, "err empty result has no OBJ solid"); return;
      end if;
      if Ada.Directories.Exists (Temp) then
         Set (R, False, "err temporary output already exists"); return;
      end if;
      Ada.Text_IO.Create (F, Ada.Text_IO.Out_File, Temp);
      Ada.Text_IO.Put_Line (F, "# Forge Wavefront OBJ; units millimetres; profile floating");
      Ada.Text_IO.Put_Line (F, "o " & Image (D.Solids (I).N));
      declare
         M : Tri_Mesh renames D.Solids (I).M.all;
      begin
         for J in 1 .. M.NV loop
            Ada.Text_IO.Put_Line (F, OBJ.Vertex_Line (M.V (J)));
         end loop;
         Ada.Text_IO.Put_Line (F, "s off");
         for J in 1 .. M.NT loop
            Ada.Text_IO.Put_Line (F, OBJ.Face_Line
              (Positive (M.T (J).A), Positive (M.T (J).B), Positive (M.T (J).C)));
         end loop;
      end;
      Ada.Text_IO.Close (F);
      GNAT.OS_Lib.Rename_File (Temp, Path, Good);
      if Good then
         Set (R, True, "ok wrote OBJ " & Path);
      else
         Ada.Directories.Delete_File (Temp);
         Set (R, False, "err cannot replace " & Path);
      end if;
   exception
      when Ada.Text_IO.Name_Error | Ada.Text_IO.Use_Error | Ada.Text_IO.Device_Error =>
         if Ada.Text_IO.Is_Open (F) then
            Ada.Text_IO.Close (F);
         end if;
         if Ada.Directories.Exists (Temp) then
            Ada.Directories.Delete_File (Temp);
         end if;
         Set (R, False, "err cannot write OBJ " & Path);
   end Do_Export;

   procedure Do_Load (S : in out Session; Path : String; R : out Response);

   procedure Do_Load (S : in out Session; Path : String; R : out Response) is
      F : Ada.Text_IO.File_Type;
      Candidate : Session;
      Line_No : Natural := 0;
      C : Command;
      Good : Boolean;
      Error : Path_String;
   begin
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, Path);
      while not Ada.Text_IO.End_Of_File (F) loop
         declare
            Line : constant String := Ada.Text_IO.Get_Line (F);
            Normal : constant String := Ada.Strings.Fixed.Trim (Line, Ada.Strings.Both);
         begin
            Line_No := Line_No + 1;
            if Line'Length > Max_Line then
               Set (R, False, "err document line too long");
            elsif Normal'Length >= 14 and then Normal (Normal'First .. Normal'First + 13)
              = "# forge-format" and then Normal /= Header
            then
               Set (R, False, "err unsupported document version or numeric profile");
            else
               Parse (Line, C, Good, Error);
               if not Good then
                  Set (R, False, "err " & Image (Error));
               elsif C.K not in Modeling | Comment | Empty then
                  Set (R, False, "err document contains non-modeling command");
               else
                  Execute (Candidate, Line, R);
               end if;
            end if;
            if not R.Ok then
               Ada.Text_IO.Close (F);
               declare
                  Msg : constant String := Image (R);
               begin
                  Set (R, False, "err line" & Line_No'Image & ": " & Msg);
               end;
               return;
            end if;
         end;
      end loop;
      Ada.Text_IO.Close (F);
      Dispose (S.Data);
      S.Data := Candidate.Data; Candidate.Data := null;
      S.History := Candidate.History;
      S.Cursor := Candidate.Cursor;
      Set (R, True, "ok loaded" & S.Cursor.Applied'Image & " commands");
   exception
      when Ada.Text_IO.Name_Error | Ada.Text_IO.Use_Error | Ada.Text_IO.Device_Error =>
         if Ada.Text_IO.Is_Open (F) then
            Ada.Text_IO.Close (F);
         end if;
         Set (R, False, "err cannot read " & Path);
   end Do_Load;

   procedure Execute (S : in out Session; Line : String; R : out Response) is
      C : Command;
      Good : Boolean;
      Error : Path_String;
      D : State_Access := null;
      I, Count : Natural;
      Id : Model.Node_Id;
   begin
      if Line'Length > Max_Line then
         Set (R, False, "err line too long"); return;
      end if;
      Parse (Line, C, Good, Error);
      if not Good then
         Set (R, False, "err " & Image (Error)); return;
      end if;
      case C.K is
         when Modeling =>
            if S.Cursor.Applied = Max_History then
               Set (R, False, "err history full"); return;
            end if;
            Rebuild (S, S.Cursor.Applied, D, R);
            if R.Ok then
               Apply (D.all, C, R);
               if R.Ok then
                  for Item of D.Solids loop
                     if Item.Used and then not Model.Valid_Subtree (D.Tree, Item.Root) then
                        Set (R, False, "err expression depth, cycle or arity invalid");
                        exit;
                     end if;
                  end loop;
               end if;
            end if;
            if R.Ok then
               Dispose (S.Data); S.Data := D; D := null;
               Forge.History.Commit_Edit (S.Cursor);
               S.History (S.Cursor.Applied) := C;
            end if;
            Dispose (D);
         when Undo | Redo =>
            if C.K = Undo and then S.Cursor.Applied = 0 then
               Set (R, False, "err nothing to undo"); return;
            elsif C.K = Redo and then S.Cursor.Applied = S.Cursor.Stored then
               Set (R, False, "err nothing to redo"); return;
            end if;
            Count := (if C.K = Undo then S.Cursor.Applied - 1 else S.Cursor.Applied + 1);
            Rebuild (S, Count, D, R);
            if R.Ok then
               Dispose (S.Data); S.Data := D; D := null;
               if C.K = Undo then
                  Forge.History.Undo (S.Cursor);
               else
                  Forge.History.Redo (S.Cursor);
               end if;
               Set (R, True, "ok history" & Count'Image);
            end if;
            Dispose (D);
         when List =>
            Set (R, True, "ok");
            if S.Data /= null then
               for Item of S.Data.Solids loop
                  if Item.Used then
                     Append (R, " " & Image (Item.N));
                  end if;
               end loop;
            end if;
         when Tree | Info | Evaluate | Inspect_Bounds | Export | Params =>
            I := Find (S.Data, (if C.K = Export then C.Ex_Name
                               elsif C.K = Params then C.Param_Name else C.Target));
            if I = 0 then
               Set (R, False, "err no such named object"); return;
            end if;
            if C.K = Tree then
               Set (R, True, "ok");
               Describe (S.Data.all, S.Data.Solids (I).Root, R);
            elsif C.K = Inspect_Bounds then
               declare
                  B : Model_Bounds.Box;
               begin
                  Model_Bounds.Evaluate (S.Data.Tree, S.Data.Solids (I).Root, B, Good);
                  if not Good then
                     Set (R, False, "err conservative bound outside numeric domain");
                  elsif B.Empty then
                     Set (R, True, "ok conservative bounds empty");
                  else
                     Set (R, True, "ok conservative min" & B.Lo.X'Image & B.Lo.Y'Image
                          & B.Lo.Z'Image & " max" & B.Hi.X'Image & B.Hi.Y'Image & B.Hi.Z'Image);
                  end if;
               end;
            elsif C.K = Params then
               Id := Model.Resolve (S.Data.Tree, S.Data.Solids (I).Root, Image (C.Param_Path));
               if Id = 0 then
                  Set (R, False, "err invalid subtree path");
               else
                  Set (R, True, "ok " & Image (S.Data.Tree.Nodes (Id).Payload));
               end if;
            elsif C.K = Export then
               Do_Export (S.Data, I, Image (C.Ex_Path), R);
            else
               Evaluate_Solid (S.Data, I, R);
               if C.K = Info and then R.Ok then
                  declare
                     M : Tri_Mesh renames S.Data.Solids (I).M.all;
                     Lo, Hi : Vec3;
                  begin
                     Set (R, True, "ok " & Image (S.Data.Solids (I).N));
                     Append (R, " profile floating vertices" & M.NV'Image
                             & " triangles" & M.NT'Image
                             & (if M.NT = 0 then " empty yes" else " solid yes")
                             & " volume" & Volume (M)'Image);
                     if M.NT /= 0 then
                        Bounds (M, Lo, Hi);
                        Append (R, " min" & Lo.X'Image & Lo.Y'Image & Lo.Z'Image
                                & " max" & Hi.X'Image & Hi.Y'Image & Hi.Z'Image);
                     else
                        Append (R, " bounds none");
                     end if;
                  end;
               end if;
            end if;
         when Save =>
            declare
               Length : Natural := Header'Length + 1;
            begin
               for J in 1 .. S.Cursor.Applied loop
                  Length := Length + Image (S.History (J))'Length + 1;
               end loop;
               declare
                  Text : String (1 .. Length);
                  At_Pos : Positive := 1;
                  procedure Put (Value : String);

                  procedure Put (Value : String) is
                  begin
                     Text (At_Pos .. At_Pos + Value'Length - 1) := Value;
                     At_Pos := At_Pos + Value'Length;
                     Text (At_Pos) := ASCII.LF; At_Pos := At_Pos + 1;
                  end Put;
               begin
                  Put (Header);
                  for J in 1 .. S.Cursor.Applied loop
                     Put (Image (S.History (J)));
                  end loop;
                  Write_File (Image (C.File), Text, R);
               end;
            end;
         when Load => Do_Load (S, Image (C.File), R);
         when Comment | Empty => Set (R, True, "ok");
      end case;
   exception
      when Storage_Error =>
         Dispose (D);
         Set (R, False, "err capacity exceeded: session memory");
   end Execute;

   function Solid_Count (S : Session) return Natural is
      Count : Natural := 0;
   begin
      if S.Data /= null then
         for Item of S.Data.Solids loop
            if Item.Used then
               Count := Count + 1;
            end if;
         end loop;
      end if;
      return Count;
   end Solid_Count;

   function Solid_Name (S : Session; I : Positive) return Name is
      Count : Natural := 0;
   begin
      if S.Data /= null then
         for Item of S.Data.Solids loop
            if Item.Used then
               Count := Count + 1;
               if Count = I then
                  return Item.N;
               end if;
            end if;
         end loop;
      end if;
      return To_Name ("");
   end Solid_Name;

   function Has_Solid (S : Session; N : Name) return Boolean is (Find (S.Data, N) /= 0);

   function Mesh_Of (S : Session; N : Name) return Mesh_View is
      I : constant Positive := Find (S.Data, N);
      R : Response;
   begin
      Evaluate_Solid (S.Data, I, R);
      return (if R.Ok then Mesh_View (S.Data.Solids (I).M) else null);
   end Mesh_Of;

   function History_Length (S : Session) return Natural is (S.Cursor.Applied);
   function History_Line (S : Session; I : Positive) return String is (Image (S.History (I)));
end Forge.Session;
