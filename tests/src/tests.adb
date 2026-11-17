pragma Warnings (Off, "static fixed-point value is not a multiple of Small");
--  Unit tests. Plain Ada, no framework, non-zero exit on failure.

with Ada.Command_Line;
with Ada.Directories;
with GNAT.OS_Lib;
with Ada.Text_IO;      use Ada.Text_IO;
with Forge;            use Forge;
with Forge.Commands;   use Forge.Commands;
with Forge.Mesh;       use Forge.Mesh;
with Forge.Primitives;
with Forge.Session;    use Forge.Session;
with Forge.Solid_Trees; use Forge.Solid_Trees;
with Forge.STL;
with Forge.Transform;

procedure Tests is

   Failures : Natural := 0;

   procedure Check (Name : String; Cond : Boolean);
   procedure Test_Mesh;
   procedure Test_Primitives;
   procedure Test_STL;
   procedure Test_Commands;
   procedure Test_Session;
   procedure Test_Fixed;
   procedure Test_Tree;

   procedure Check (Name : String; Cond : Boolean) is
   begin
      Put_Line ((if Cond then "PASS  " else "FAIL  ") & Name);
      if not Cond then
         Failures := Failures + 1;
      end if;
   end Check;

   function Near (A, B : Scalar; Tol : Scalar := 1.0e-9) return Boolean is
     (abs (A - B) <= Tol * Scalar'Max (1.0, abs B));

   ---------------------------------------------------------------------

   procedure Test_Fixed is
      M : Tri_Mesh (16, 32);
      Ok : Boolean;
      Before : Vec3;
      C, D : Command;
      Err : Path_String;
      S : Forge.Session.Session;
      R : Response;
   begin
      Check ("fixed grid resolution", Scalar'Small = 2.0 ** (-32));
      Check ("fixed square root", Near (Length ((3.0, 4.0, 0.0)), 5.0));
      Primitives.Box (M, 10_000.0, 10_000.0, 10_000.0, Ok);
      Check ("volume has range beyond coordinates", Ok and then Volume (M) = 1.0e12);
      Parse ("translate a -0.00000000023283064365386962890625 0.1 0", C, Ok, Err);
      Check ("parse one negative grid unit", Ok and then C.By.X = -Scalar'Small);
      Parse (Image (C), D, Ok, Err);
      Check ("fixed decimals round trip exactly", Ok and then C.By = D.By);
      Primitives.Box (M, 2.0, 2.0, 2.0, Ok);
      Before := M.V (1);
      for I in 1 .. 4 loop
         Forge.Transform.Rotate (M, Z, 90.0);
      end loop;
      Check ("four quarter turns are exact", M.V (1) = Before);
      begin
         Forge.Transform.Translate (M, (10_000.0, 0.0, 0.0));
         Check ("out of range transform rejected", False);
      exception
         when Constraint_Error =>
            Check ("failed transform leaves vertices unchanged", M.V (1) = Before);
      end;
      Primitives.Box (M, Scalar'Small, 2.0, 2.0, Ok);
      Check ("collapsed box rejected", not Ok and then M.NT = 0);
      Execute (S, "box a 2 2 2", R);
      Execute (S, "translate a 10000 0 0", R);
      Check ("failed numeric edit is not recorded", not R.Ok and History_Length (S) = 1);
      Execute (S, "info a", R);
      Check ("session survives numeric failure", R.Ok);
   end Test_Fixed;

   procedure Test_Mesh is
      M  : Tri_Mesh (16, 32);
      Ok : Boolean;
      V1, V2, V3, V4 : Vertex_Index;
   begin
      Clear (M);
      Check ("empty is well formed", Well_Formed (M));
      Check ("empty is not solid", not Is_Solid (M));

      --  A tetrahedron, outward CCW.
      Add_Vertex (M, (0.0, 0.0, 0.0), V1, Ok);
      Add_Vertex (M, (1.0, 0.0, 0.0), V2, Ok);
      Add_Vertex (M, (0.0, 1.0, 0.0), V3, Ok);
      Add_Vertex (M, (0.0, 0.0, 1.0), V4, Ok);
      Add_Triangle (M, V1, V3, V2, Ok);   --  bottom, faces -Z
      Add_Triangle (M, V1, V2, V4, Ok);   --  faces -Y
      Add_Triangle (M, V1, V4, V3, Ok);   --  faces -X
      Add_Triangle (M, V2, V3, V4, Ok);   --  slanted
      Check ("tetra well formed", Well_Formed (M));
      Check ("tetra watertight", Is_Watertight (M));
      Check ("tetra volume 1/6", Near (Volume (M), 1.0 / 6.0));

      --  Break it: one triangle flipped.
      M.T (4) := (V3, V2, V4);
      Check ("flipped triangle is not watertight", not Is_Watertight (M));
      M.T (4) := (V2, V3, V4);

      --  Break it: one triangle missing.
      M.NT := 3;
      Check ("open mesh is not watertight", not Is_Watertight (M));
   end Test_Mesh;

   procedure Test_Primitives is
      M  : Tri_Mesh (1024, 2048);
      Ok : Boolean;
      Lo, Hi : Vec3;
   begin
      Primitives.Box (M, 2.0, 3.0, 4.0, Ok);
      Check ("box ok", Ok);
      Check ("box is solid", Is_Solid (M));
      Check ("box volume", Near (Volume (M), 24.0));
      Bounds (M, Lo, Hi);
      Check ("box centred", Near (Lo.X, -1.0) and Near (Hi.Z, 2.0));

      Primitives.Cylinder (M, 1.0, 2.0, 64, Ok);
      Check ("cylinder ok", Ok);
      Check ("cylinder is solid", Is_Solid (M));
      Check ("cylinder counts", M.NV = 130 and M.NT = 256);
      Check ("cylinder volume approx pi*2", Near (Volume (M), 6.2832, 2.0e-3));

      Transform.Translate (M, (5.0, 0.0, 0.0));
      Check ("translate keeps volume", Near (Volume (M), 6.2832, 2.0e-3) and Is_Solid (M));
      Transform.Rotate (M, X, 90.0);
      Check ("rotate keeps solid", Is_Solid (M));
      Transform.Scale (M, 2.0);
      Check ("scale x2 gives x8 volume", Near (Volume (M), 8.0 * 6.2832, 2.0e-3));
      Primitives.Sphere (M, 1.0, Ok);
      Check ("sphere counts and topology", Ok and then M.NV = 114
             and then M.NT = 224 and then Is_Solid (M));
      Check ("sphere outward volume", Volume (M) > 3.8 and Volume (M) < 4.2);
      Primitives.Sphere (M, Scalar'Small, Ok);
      Check ("collapsed sphere rejected", not Ok and M.NT = 0);
   end Test_Primitives;

   procedure Test_STL is
      M   : Tri_Mesh (16, 32);
      Ok  : Boolean;
      Buf : STL.Byte_Array (1 .. 1000);
      Last : Natural;
   begin
      Primitives.Box (M, 1.0, 1.0, 1.0, Ok);
      Check ("stl size 84 + 50*12", STL.Size (M) = 684);
      STL.Write (M, Buf, Last);
      Check ("stl wrote exactly Size", Last = 684);
      Check ("stl count field = 12", Natural (Buf (81)) = 12 and Natural (Buf (82)) = 0);
   end Test_STL;

   procedure Test_Commands is
      C, D : Command;
      Ok   : Boolean;
      Err  : Path_String;
      procedure Round_Trip (L : String);
      procedure Round_Trip (L : String) is
      begin
         Parse (L, C, Ok, Err);
         Check ("parse: " & L, Ok);
         Parse (Image (C), D, Ok, Err);
         Check ("round trip: " & Image (C), Ok and then Image (D) = Image (C));
      end Round_Trip;
   begin
      Round_Trip ("box a 1 2.5 3");
      Round_Trip ("cylinder c 1 2 12");
      Round_Trip ("translate a -1 0 2.25");
      Round_Trip ("rotate a y 45");
      Round_Trip ("scale a 0.5");
      Round_Trip ("union u a c");
      Round_Trip ("difference d a c");
      Round_Trip ("copy k a");
      Round_Trip ("delete k");
      Round_Trip ("cube c 2 1.5 2 3 0.125");
      Round_Trip ("sphere s 0.125");
      Round_Trip ("move c 1 2 3");
      Round_Trip ("resize c 0.1");
      Round_Trip ("intersect g a b c d");
      Round_Trip ("difference g a b c");
      Round_Trip ("tree");
      Round_Trip ("history");
      Round_Trip ("redo");
      Round_Trip ("export workspace.stl");

      Parse ("box a 1 2", C, Ok, Err);
      Check ("too few args rejected", not Ok);
      Parse ("box bad-name 1 2 3", C, Ok, Err);
      Check ("bad name rejected", not Ok);
      Parse ("frobnicate x", C, Ok, Err);
      Check ("unknown verb rejected", not Ok);
      Parse ("# a comment", C, Ok, Err);
      Check ("comment", Ok and C.K = Comment);
      Parse ("   ", C, Ok, Err);
      Check ("blank", Ok and C.K = Empty);
      Parse ("cylinder c 1 2 2", C, Ok, Err);
      Check ("segments < 3 rejected", not Ok);
   end Test_Commands;

   procedure Test_Session is
      S : Forge.Session.Session;
      R : Response;
   begin
      Execute (S, "box a 10 10 10", R);
      Check ("session box", R.Ok and Solid_Count (S) = 1);
      Execute (S, "info a", R);
      Check ("info reports solid", R.Ok and then (for some I in 1 .. R.Length - 8 =>
                                                   R.Text (I .. I + 8) = "solid yes"));
      Execute (S, "translate a 1 0 0", R);
      Execute (S, "copy b a", R);
      Check ("copy", R.Ok and Solid_Count (S) = 2 and History_Length (S) = 3);
      Execute (S, "info nothere", R);
      Check ("unknown solid is an error", not R.Ok);
      Execute (S, "union u a b", R);
      Check ("csg records a group", R.Ok and Solid_Count (S) = 3 and History_Length (S) = 4);
      Execute (S, "undo", R);
      Check ("undo removes group", R.Ok and Solid_Count (S) = 2 and History_Length (S) = 3);
      Execute (S, "undo", R);
      Execute (S, "undo", R);
      Execute (S, "undo", R);
      Check ("undo to empty", Solid_Count (S) = 0 and History_Length (S) = 0);
      Execute (S, "undo", R);
      Check ("undo on empty is an error", not R.Ok);
      Execute (S, "box a 1 1 1", R);
      Execute (S, "scale a 0", R);
      Check ("bad scale rejected, not recorded", not R.Ok and History_Length (S) = 1);
      Check ("mesh view", Mesh_Of (S, To_Name ("a")).NT = 12);
      Check ("history line", History_Line (S, 1) = "box a 1 1 1");
   end Test_Session;

   procedure Test_Tree is
      use type Ada.Directories.File_Size;
      S, Loaded : Forge.Session.Session;
      R : Response;
      PID : constant String :=
        GNAT.OS_Lib.Pid_To_Integer (GNAT.OS_Lib.Current_Process_Id)'Image;
      Path : constant String := "/tmp/forge-tree-" & PID (2 .. PID'Last);
      procedure Edit (Line : String);
      procedure Edit (Line : String) is
      begin
         Execute (S, Line, R);
         Check (Line, R.Ok);
      end Edit;
   begin
      Edit ("cube a 2");
      Edit ("cube b 2");
      Edit ("union g a b");
      Edit ("move g 9000 0 0");
      Edit ("move a -9000 0 0");
      Edit ("resize g 0.5");
      declare
         Lo, Hi : Vec3;
      begin
         Bounds (Mesh_Of (S, To_Name ("a")).all, Lo, Hi);
         Check ("pivot resize accepts valid final coordinates", Lo.X = -0.5 and Hi.X = 0.5);
         Bounds (Mesh_Of (S, To_Name ("b")).all, Lo, Hi);
         Check ("pivot resize keeps other child near pivot", Lo.X = 8999.5 and Hi.X = 9000.5);
      end;
      Edit ("move a 1 0 0");
      Edit ("undo");
      declare
         Tree : constant Node_Array := View_Tree (S);
         History : constant Command_Array := View_History (S, True);
         Before : constant Vec3 := Mesh_Of (S, To_Name ("a")).V (1);
      begin
         Execute (S, "move g 10000 0 0", R);
         Check ("failed group transform restores earlier child", not R.Ok
                and then Mesh_Of (S, To_Name ("a")).V (1) = Before);
         Check ("failed edit preserves tree and redo", View_Tree (S) = Tree
                and View_History (S, True) = History and History_Length (S) = 6);
         Execute (S, "resize g 0.00000000023283064365386962890625", R);
         Check ("collapsed resize restores state", not R.Ok and then View_Tree (S) = Tree);
      end;
      Edit ("redo");
      Edit ("undo");
      Edit ("sphere s 1");
      Execute (S, "redo", R);
      Check ("successful edit discards redo", not R.Ok);
      Edit ("difference nested g s");
      Check ("nested Boolean has no evaluated mesh", Mesh_Of (S, To_Name ("nested")) = null);
      Execute (S, "union invalid a s", R);
      Check ("non-sibling operands rejected", not R.Ok);
      Execute (S, "union invalid a a", R);
      Check ("duplicate operands rejected", not R.Ok);
      Edit ("save " & Path & ".forge");
      Execute (Loaded, "load " & Path & ".forge", R);
      Check ("saved nested tree replays exactly", R.Ok and then View_Tree (Loaded) = View_Tree (S)
             and then View_History (Loaded) = View_History (S));
      Execute (S, "export " & Path & ".stl", R);
      Check ("workspace export rejects unresolved group", not R.Ok
             and then not Ada.Directories.Exists (Path & ".stl"));
      Edit ("delete nested");
      Check ("delete removes complete subtree", Solid_Count (S) = 0);
      Edit ("undo");
      Check ("undo restores subtree", View_Tree (S) = View_Tree (Loaded));
      Edit ("redo");
      Check ("redo deletes subtree", Solid_Count (S) = 0);

      declare
         N : constant Forge.Name := Make_Cube (S, 1000.0, Scale => 0.00001);
         Before : constant Vec3 := Mesh_Of (S, N).V (1);
         Sphere_Name : Forge.Name;
      begin
         Scale_Shape (S, N, 0.00001);
         Check ("small absolute scale is idempotent", Mesh_Of (S, N).V (1) = Before);
         Move_Shape (S, N, 5.0, 0.0, 0.0);
         Sphere_Name := Make_Sphere (S, 1.0, X => -5.0);
         Check ("typed sphere builds a solid", Is_Solid (Mesh_Of (S, Sphere_Name).all));
         Forge.Session.Undo (S);
         Execute (S, "save " & Path & "-active.forge", R);
         Check ("save while undone succeeds", R.Ok);
         Execute (Loaded, "load " & Path & "-active.forge", R);
         Check ("save keeps only active prefix", R.Ok and then View_Tree (Loaded) = View_Tree (S)
                and then View_History (Loaded, True)'Length = History_Length (S));
         Forge.Session.Export (S, Path & ".stl");
         Check ("typed export writes STL", Ada.Directories.Size (Path & ".stl") = 684);
         Forge.Session.Redo (S);
         Check ("export preserves redo", Has_Solid (S, Sphere_Name));
         declare
            Group : constant Forge.Name := Subtraction (S, Name_Array'[Sphere_Name, N]);
         begin
            Check ("typed group preserves operand order",
                   (for some Item of View_Tree (S) => Item.N = Sphere_Name
                    and then Item.Parent = Group and then Item.Order = 1));
            Forge.Session.Undo (S);
         end;
         Delete_Shape (S, N);
         Delete_Shape (S, Sphere_Name);
         begin
            Forge.Session.Export (S, Path & ".stl");
            Check ("typed empty export raises", False);
         exception
            when Invalid_Command =>
               Check ("typed empty export preserves destination",
                      Ada.Directories.Size (Path & ".stl") = 684);
         end;
      end;

      Ada.Directories.Delete_File (Path & ".stl");
      Ada.Directories.Delete_File (Path & ".forge");
      Ada.Directories.Delete_File (Path & "-active.forge");
   end Test_Tree;

begin
   Test_Tree;
   Test_Fixed;
   Test_Mesh;
   Test_Primitives;
   Test_STL;
   Test_Commands;
   Test_Session;
   New_Line;
   if Failures = 0 then
      Put_Line ("all tests passed");
   else
      Put_Line (Failures'Image & " failure(s)");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Tests;
