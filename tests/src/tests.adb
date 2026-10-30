pragma Warnings (Off, "static fixed-point value is not a multiple of Small");
--  Unit tests. Plain Ada, no framework, non-zero exit on failure.

with Ada.Command_Line;
with Ada.Text_IO;      use Ada.Text_IO;
with Forge;            use Forge;
with Forge.Commands;   use Forge.Commands;
with Forge.Mesh;       use Forge.Mesh;
with Forge.Primitives;
with Forge.Session;    use Forge.Session;
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
      Check ("csg reports not implemented", not R.Ok and History_Length (S) = 3);
      Execute (S, "undo", R);
      Check ("undo removes copy", R.Ok and Solid_Count (S) = 1 and History_Length (S) = 2);
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

begin
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
