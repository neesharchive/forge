with Ada.Streams.Stream_IO;
with Ada.Text_IO;
with Ada.Unchecked_Deallocation;
with Forge.CSG;
with Forge.Primitives;
with Forge.STL;
with Forge.Transform;

package body Forge.Session is

   procedure Free is new Ada.Unchecked_Deallocation (Tri_Mesh, Mesh_Access);
   pragma Unreferenced (Free);
   --  Meshes are allocated once per slot and reused; nothing frees them
   --  before the program ends. Kept for a future Session finalizer.

   procedure Set (R : out Response; Ok : Boolean; Msg : String) renames Responses.Set;
   procedure Append (R : in out Response; Msg : String) renames Responses.Append;
   function Find (S : Session; N : Name) return Natural;
   function Slot_For (S : in out Session; N : Name) return Natural;
   procedure Release (S : in out Session; I : Positive);
   procedure Clear_Solids (S : in out Session);
   procedure Apply (S : in out Session; C : Command; R : out Response);
   procedure Replay (S : in out Session);
   procedure Do_Info (S : Session; N : Name; R : out Response);
   procedure Do_List (S : Session; R : out Response);
   procedure Do_Export (S : Session; N : Name; Path : String; R : out Response);
   procedure Do_Save (S : Session; Path : String; R : out Response);
   procedure Do_Load (S : in out Session; Path : String; R : out Response);

   ---------------------------------------------------------------------
   --  Responses
   ---------------------------------------------------------------------

   ---------------------------------------------------------------------
   --  Solid table
   ---------------------------------------------------------------------

   function Find (S : Session; N : Name) return Natural is
   begin
      for I in S.Solids'Range loop
         if S.Solids (I).Used and then S.Solids (I).N = N then
            return I;
         end if;
      end loop;
      return 0;
   end Find;

   --  Returns the slot for N, creating (and allocating) it if absent.
   --  0 when the table is full.
   function Slot_For (S : in out Session; N : Name) return Natural is
      I : constant Natural := Find (S, N);
   begin
      if I /= 0 then
         return I;
      end if;
      for J in S.Solids'Range loop
         if not S.Solids (J).Used then
            S.Solids (J).Used := True;
            S.Solids (J).N := N;
            if S.Solids (J).M = null then
               S.Solids (J).M := new Tri_Mesh (Default_Cap_V, Default_Cap_T);
               Clear (S.Solids (J).M.all);
            end if;
            return J;
         end if;
      end loop;
      return 0;
   end Slot_For;

   procedure Release (S : in out Session; I : Positive) is
   begin
      S.Solids (I).Used := False;
      Clear (S.Solids (I).M.all);
   end Release;

   procedure Clear_Solids (S : in out Session) is
   begin
      for I in S.Solids'Range loop
         if S.Solids (I).Used then
            Release (S, I);
         end if;
      end loop;
   end Clear_Solids;

   ---------------------------------------------------------------------
   --  Apply one modeling command to the solids. No history here.
   ---------------------------------------------------------------------

   procedure Apply (S : in out Session; C : Command; R : out Response) is
      Ok : Boolean;

      function Need (N : Name) return Natural;
      procedure Ensure_Solid (I : Positive);

      function Need (N : Name) return Natural is
         I : constant Natural := Find (S, N);
      begin
         if I = 0 then
            Set (R, False, "err no solid named " & Image (N));
         end if;
         return I;
      end Need;

      procedure Ensure_Solid (I : Positive) is
      begin
         if not Is_Solid (S.Solids (I).M.all) then
            Release (S, I);
            Set (R, False, "err kernel produced a non-solid mesh; discarded");
         end if;
      end Ensure_Solid;

   begin
      Set (R, True, "ok");
      case C.K is
         when Box =>
            declare
               I : constant Natural := Slot_For (S, C.Box_Name);
            begin
               if I = 0 then
                  Set (R, False, "err solid table full"); return;
               end if;
               Primitives.Box (S.Solids (I).M.all, C.W, C.H, C.D, Ok);
               if not Ok then
                  Release (S, I); Set (R, False, "err mesh capacity"); return;
               end if;
               Ensure_Solid (I);
            end;

         when Cylinder =>
            declare
               I : constant Natural := Slot_For (S, C.Cyl_Name);
            begin
               if I = 0 then
                  Set (R, False, "err solid table full"); return;
               end if;
               Primitives.Cylinder (S.Solids (I).M.all, C.R, C.CH, C.Segments, Ok);
               if not Ok then
                  Release (S, I); Set (R, False, "err mesh capacity"); return;
               end if;
               Ensure_Solid (I);
            end;

         when Translate =>
            declare
               I : constant Natural := Need (C.Tr_Name);
            begin
               if I /= 0 then
                  Transform.Translate (S.Solids (I).M.all, C.By);
               end if;
            end;

         when Rotate =>
            declare
               I : constant Natural := Need (C.Rot_Name);
            begin
               if I /= 0 then
                  Transform.Rotate (S.Solids (I).M.all, C.About, C.Degrees);
               end if;
            end;

         when Scale =>
            declare
               I : constant Natural := Need (C.Sc_Name);
            begin
               if I /= 0 then
                  if C.Factor <= 0.0 then
                     Set (R, False, "err scale factor must be positive");
                  else
                     Transform.Scale (S.Solids (I).M.all, C.Factor);
                  end if;
               end if;
            end;

         when Union | Difference | Intersect =>
            declare
               IA : constant Natural := Need (C.A);
               IB : Natural := 0;
               IR : Natural := 0;
               Reason : CSG.Reason_String;
               Last   : Natural;
               Op : constant CSG.Operation :=
                 (case C.K is when Union => CSG.Union, when Difference => CSG.Difference,
                               when others => CSG.Intersection);
            begin
               if IA = 0 then
                  return;
               end if;
               IB := Need (C.B);
               if IB = 0 then
                  return;
               end if;
               if C.Result = C.A or else C.Result = C.B then
                  Set (R, False, "err result must be a new name (in-place csg is a milestone)");
                  return;
               end if;
               IR := Slot_For (S, C.Result);
               if IR = 0 then
                  Set (R, False, "err solid table full"); return;
               end if;
               CSG.Apply (Op, S.Solids (IA).M.all, S.Solids (IB).M.all,
                          S.Solids (IR).M.all, Ok, Reason, Last);
               if not Ok then
                  Release (S, IR);
                  Set (R, False, "err " & Reason (1 .. Last));
                  return;
               end if;
               Ensure_Solid (IR);
            end;

         when Copy =>
            declare
               Src : constant Natural := Need (C.From);
               IT  : Natural;
            begin
               if Src = 0 then
                  return;
               end if;
               IT := Slot_For (S, C.Cp_Name);
               if IT = 0 then
                  Set (R, False, "err solid table full"); return;
               end if;
               Mesh.Copy (S.Solids (Src).M.all, S.Solids (IT).M.all, Ok);
               if not Ok then
                  Release (S, IT); Set (R, False, "err mesh capacity");
               end if;
            end;

         when Delete =>
            declare
               I : constant Natural := Need (C.Target);
            begin
               if I /= 0 then
                  Release (S, I);
               end if;
            end;

         when others =>
            Set (R, False, "err not a modeling command");
      end case;
   exception
      when Constraint_Error =>
         Set (R, False, "err outside fixed-point modeling range");
   end Apply;

   ---------------------------------------------------------------------
   --  Replay the history from empty
   ---------------------------------------------------------------------

   procedure Replay (S : in out Session) is
      R : Response;
   begin
      Clear_Solids (S);
      for I in 1 .. S.Count loop
         Apply (S, S.History (I), R);
         --  Every line in the history succeeded once; a failure here
         --  means the kernel is non-deterministic, which is a bug.
      end loop;
   end Replay;

   ---------------------------------------------------------------------
   --  Queries and side effects
   ---------------------------------------------------------------------

   procedure Do_Info (S : Session; N : Name; R : out Response) is
      I : constant Natural := Find (S, N);
   begin
      if I = 0 then
         Set (R, False, "err no solid named " & Image (N));
         return;
      end if;
      declare
         M : Tri_Mesh renames S.Solids (I).M.all;
         Lo, Hi : Vec3;
      begin
         Bounds (M, Lo, Hi);
         Set (R, True, "ok " & Image (N));
         Append (R, " vertices" & M.NV'Image & " triangles" & M.NT'Image);
         Append (R, " solid " & (if Is_Solid (M) then "yes" else "NO"));
         Append (R, " volume" & Volume (M)'Image);
         Append (R, " min" & Lo.X'Image & Lo.Y'Image & Lo.Z'Image);
         Append (R, " max" & Hi.X'Image & Hi.Y'Image & Hi.Z'Image);
      end;
   end Do_Info;

   procedure Do_List (S : Session; R : out Response) is
   begin
      Set (R, True, "ok");
      for I in S.Solids'Range loop
         if S.Solids (I).Used then
            Append (R, " " & Image (S.Solids (I).N));
         end if;
      end loop;
   end Do_List;

   procedure Do_Export (S : Session; N : Name; Path : String; R : out Response) is
      use Ada.Streams.Stream_IO;
      I : constant Natural := Find (S, N);
      F : File_Type;
   begin
      if I = 0 then
         Set (R, False, "err no solid named " & Image (N));
         return;
      end if;
      declare
         M    : Tri_Mesh renames S.Solids (I).M.all;
         Buf  : STL.Byte_Array (1 .. STL.Size (M));
         Last : Natural;
         Elems : Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Buf'Length))
           with Import, Address => Buf'Address;
      begin
         STL.Write (M, Buf, Last);
         Create (F, Out_File, Path);
         Write (F, Elems (1 .. Ada.Streams.Stream_Element_Offset (Last)));
         Close (F);
         Set (R, True, "ok wrote" & Last'Image & " bytes to " & Path);
      end;
   exception
      when others =>
         Set (R, False, "err cannot write " & Path);
   end Do_Export;

   procedure Do_Save (S : Session; Path : String; R : out Response) is
      use Ada.Text_IO;
      F : File_Type;
   begin
      Create (F, Out_File, Path);
      Put_Line (F, "# forge document, one command per line");
      for I in 1 .. S.Count loop
         Put_Line (F, Image (S.History (I)));
      end loop;
      Close (F);
      Set (R, True, "ok saved" & S.Count'Image & " commands to " & Path);
   exception
      when others =>
         Set (R, False, "err cannot write " & Path);
   end Do_Save;

   procedure Do_Load (S : in out Session; Path : String; R : out Response) is
      use Ada.Text_IO;
      F : File_Type;
      Line_No : Natural := 0;
   begin
      Open (F, In_File, Path);
      Clear_Solids (S);
      S.Count := 0;
      while not End_Of_File (F) loop
         declare
            Line : constant String := Get_Line (F);
            RL   : Response;
         begin
            Line_No := Line_No + 1;
            Execute (S, Line, RL);
            if not RL.Ok then
               Close (F);
               Set (R, False, "err line" & Line_No'Image & ": " & Image (RL));
               return;
            end if;
         end;
      end loop;
      Close (F);
      Set (R, True, "ok loaded" & S.Count'Image & " commands from " & Path);
   exception
      when others =>
         Set (R, False, "err cannot read " & Path);
   end Do_Load;

   ---------------------------------------------------------------------
   --  Execute
   ---------------------------------------------------------------------

   procedure Execute (S : in out Session; Line : String; R : out Response) is
      C   : Command;
      Ok  : Boolean;
      Err : Path_String;
   begin
      if Line'Length > Max_Line then
         Set (R, False, "err line too long");
         return;
      end if;
      Parse (Line, C, Ok, Err);
      if not Ok then
         Set (R, False, "err " & Image (Err));
         return;
      end if;

      case C.K is
         when Modeling =>
            if S.Count >= Max_History then
               Set (R, False, "err history full");
               return;
            end if;
            Apply (S, C, R);
            if R.Ok then
               S.Count := S.Count + 1;
               S.History (S.Count) := C;
            end if;
         when Undo =>
            if S.Count = 0 then
               Set (R, False, "err nothing to undo");
            else
               S.Count := S.Count - 1;
               Replay (S);
               Set (R, True, "ok undid; history" & S.Count'Image);
            end if;
         when List    => Do_List (S, R);
         when Info    => Do_Info (S, C.Target, R);
         when Export  => Do_Export (S, C.Ex_Name, Image (C.Ex_Path), R);
         when Save    => Do_Save (S, Image (C.File), R);
         when Load    => Do_Load (S, Image (C.File), R);
         when Comment | Empty => Set (R, True, "ok");
      end case;
   end Execute;

   ---------------------------------------------------------------------
   --  Read-back
   ---------------------------------------------------------------------

   function Solid_Count (S : Session) return Natural is
      N : Natural := 0;
   begin
      for I in S.Solids'Range loop
         if S.Solids (I).Used then
            N := N + 1;
         end if;
      end loop;
      return N;
   end Solid_Count;

   function Solid_Name (S : Session; I : Positive) return Name is
      N : Natural := 0;
   begin
      for J in S.Solids'Range loop
         if S.Solids (J).Used then
            N := N + 1;
            if N = I then
               return S.Solids (J).N;
            end if;
         end if;
      end loop;
      return To_Name ("");
   end Solid_Name;

   function Has_Solid (S : Session; N : Name) return Boolean is (Find (S, N) /= 0);

   function Mesh_Of (S : Session; N : Name) return Mesh_View is
     (Mesh_View (S.Solids (Find (S, N)).M));

   function History_Length (S : Session) return Natural is (S.Count);

   function History_Line (S : Session; I : Positive) return String is
     (Image (S.History (I)));

end Forge.Session;
