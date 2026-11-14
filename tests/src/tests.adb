pragma Warnings (Off, "static fixed-point value is not a multiple of Small");
--  Unit tests. Plain Ada, no framework, non-zero exit on failure.

with Ada.Command_Line;
with Ada.Numerics;
with Ada.Numerics.Generic_Elementary_Functions;
with Ada.Text_IO;      use Ada.Text_IO;
with Forge;            use Forge;
with Forge.Commands;   use Forge.Commands;
with Forge.CSG;
with Forge.Exact;
with Forge.Mesh;       use Forge.Mesh;
with Forge.Primitives;
with Forge.Session;    use Forge.Session;
with Forge.STL;
with Forge.Transform;
with Forge.Validity;

procedure Tests is

   use type CSG.Outcome;
   use type Validity.Edge_Count;

   Failures : Natural := 0;

   type Check_Access is access Validity.Workspace;

   procedure Check (Name : String; Cond : Boolean);
   procedure Test_Mesh;
   procedure Test_Validity;
   procedure Test_Primitives;
   procedure Test_STL;
   procedure Test_Commands;
   procedure Test_Session;
   procedure Test_Fixed;
   procedure Test_CSG_Kernel;
   procedure Test_Exact;
   procedure Test_CSG;

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

   --  Forge.Validity on meshes built by hand, each broken a known way.
   procedure Test_Validity is
      W   : constant Check_Access :=
        new Validity.Workspace (Cap_V => 64, Cap_E => Validity.Edges_For (64));
      M   : Tri_Mesh (64, 64);
      Rep : Validity.Report;
      Ok  : Boolean;
      V   : array (1 .. 8) of Vertex_Index := [others => 0];

      procedure Corner (At_Point : Vec3; First : Positive);
      procedure Faces (Apex, Along_X, Along_Y, Along_Z : Vertex_Index);
      procedure Inspect;

      --  The corner and its three unit neighbours along X, Y, Z.
      procedure Corner (At_Point : Vec3; First : Positive) is
      begin
         Add_Vertex (M, At_Point, V (First), Ok);
         Add_Vertex (M, At_Point + (1.0, 0.0, 0.0), V (First + 1), Ok);
         Add_Vertex (M, At_Point + (0.0, 1.0, 0.0), V (First + 2), Ok);
         Add_Vertex (M, At_Point + (0.0, 0.0, 1.0), V (First + 3), Ok);
      end Corner;

      --  The outward tetrahedron on a corner and its three neighbours.
      --  Passing two neighbours swapped turns it inside out.
      procedure Faces (Apex, Along_X, Along_Y, Along_Z : Vertex_Index) is
      begin
         Add_Triangle (M, Apex, Along_Y, Along_X, Ok);
         Add_Triangle (M, Apex, Along_X, Along_Z, Ok);
         Add_Triangle (M, Apex, Along_Z, Along_Y, Ok);
         Add_Triangle (M, Along_X, Along_Y, Along_Z, Ok);
      end Faces;

      procedure Inspect is
      begin
         Validity.Inspect (M, W.all, Rep);
      end Inspect;

   begin
      Clear (M);
      Corner ((0.0, 0.0, 0.0), 1);
      Faces (V (1), V (2), V (3), V (4));
      Inspect;
      Check ("validity: tetra is a solid", Rep.Solid and Rep.Watertight and Rep.Manifold);
      Check ("validity: tetra V - E + F = 4 - 6 + 4 = 2, one shell, genus 0",
             Rep.Vertices = 4 and Rep.Edges = 6 and Rep.Euler = 2
             and Rep.Shells = 1 and Rep.Genus = 0);
      Check ("validity: tetra volume 1/6, area 3/2 + sqrt(3)/2",
             Near (Rep.Volume, 1.0 / 6.0) and Near (Rep.Area, 1.5 + 0.866_025_403_784_439));

      --  A second tetra sharing only the origin: two cones meeting at a point.
      Add_Vertex (M, (-1.0, 0.0, 0.0), V (5), Ok);
      Add_Vertex (M, (-1.0, 1.0, 0.0), V (6), Ok);
      Add_Vertex (M, (-1.0, 0.0, 1.0), V (7), Ok);
      Faces (V (5), V (1), V (6), V (7));
      Inspect;
      Check ("validity: bowtie passes the old edge test", Is_Watertight (M) and Rep.Watertight);
      Check ("validity: bowtie is caught: one nonmanifold vertex",
             Rep.Nonmanifold_Vertices = 1 and not Rep.Solid);
      Check ("validity: bowtie reason", Validity.Problem (Rep) = "1 nonmanifold vertex");
      Check ("validity: bowtie Euler 7 - 12 + 8 = 3", Rep.Euler = 3);

      Clear (M);
      Corner ((0.0, 0.0, 0.0), 1);
      Faces (V (1), V (2), V (3), V (4));
      Corner ((5.0, 0.0, 0.0), 5);
      Faces (V (5), V (6), V (7), V (8));
      Inspect;
      Check ("validity: two tetras apart: two shells, Euler 4",
             Rep.Solid and Rep.Shells = 2 and Rep.Euler = 4 and Rep.Genus = 0);

      M.NT := M.NT - 1;
      Inspect;
      Check ("validity: missing face: 3 open edges",
             Rep.Open_Edges = 3 and not Rep.Watertight and not Is_Watertight (M));
      Check ("validity: open reason", Validity.Problem (Rep) = "3 open edges");

      M.NT := M.NT + 1;
      M.T (M.NT) := (V (7), V (6), V (8));
      Inspect;
      Check ("validity: flipped face: repeated edges, agrees with Is_Watertight",
             Rep.Repeated_Edges > 0 and not Rep.Watertight and not Is_Watertight (M));

      --  Inside out: closed and manifold, but the volume is negative.
      Clear (M);
      Corner ((0.0, 0.0, 0.0), 1);
      Faces (V (1), V (3), V (2), V (4));
      Inspect;
      Check ("validity: inside out is closed but not a solid",
             Rep.Watertight and Rep.Manifold and Rep.Volume < 0.0 and not Rep.Solid);
      Check ("validity: inside out reason",
             Validity.Problem (Rep) = "inside out (volume is not positive)");

      declare
         Big  : Tri_Mesh (1024, 2048);
         WBig : constant Check_Access :=
           new Validity.Workspace (Cap_V => 1024, Cap_E => Validity.Edges_For (2048));
      begin
         Primitives.Box (Big, 2.0, 3.0, 4.0, Ok);
         Validity.Inspect (Big, WBig.all, Rep);
         Check ("validity: box 8 - 18 + 12 = 2",
                Rep.Solid and Rep.Vertices = 8 and Rep.Edges = 18 and Rep.Euler = 2);
         Primitives.Cylinder (Big, 1.0, 2.0, 64, Ok);
         Validity.Inspect (Big, WBig.all, Rep);
         Check ("validity: cylinder is a solid with no slivers",
                Rep.Solid and Rep.Genus = 0 and Rep.Slivers = 0 and Rep.Degenerate = 0);
         Check ("validity: fast check agrees with Is_Watertight on a cylinder",
                Rep.Watertight = Is_Watertight (Big));
      end;
   end Test_Validity;

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
      Round_Trip ("intersect i a c");
      Round_Trip ("difference a a c");
      Round_Trip ("check a");
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
      Check ("union of a solid and its copy is recorded",
             R.Ok and Solid_Count (S) = 3 and History_Length (S) = 4);
      Execute (S, "undo", R);
      Check ("undo removes union", R.Ok and Solid_Count (S) = 2 and History_Length (S) = 3);
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
      Execute (S, "check a", R);
      Check ("check reports a solid", R.Ok and then (for some I in 1 .. R.Length - 8 =>
                                                       R.Text (I .. I + 8) = "solid yes"));
      Check ("check is a query, not recorded", History_Length (S) = 1);

      --  Genus 2 makes Euler -2, which must print as "euler -2".
      Execute (S, "box p 6 4 2", R);
      Execute (S, "cylinder h 0.5 4 16", R);
      Execute (S, "translate h -1.5 0 0", R);
      Execute (S, "difference p p h", R);
      Execute (S, "translate h 3 0 0", R);
      Execute (S, "difference p p h", R);
      Execute (S, "check p", R);
      declare
         Want : constant String := " genus 2 euler -2 ";
      begin
         Check ("check prints a negative Euler number as its own field",
                R.Ok and then (for some I in 1 .. R.Length - Want'Length + 1 =>
                                 R.Text (I .. I + Want'Length - 1) = Want));
      end;
   end Test_Session;

   --  The kernel contract, without the session in between.
   procedure Test_CSG_Kernel is
      type Work_Access is access CSG.Workspace;
      A, B    : Tri_Mesh (64, 128);
      Result  : Tri_Mesh (256, 512);
      Check_W : constant Check_Access :=
        new Validity.Workspace (Cap_V => 256, Cap_E => Validity.Edges_For (512));
      Tiny    : CSG.Workspace (Max_Polygons => 4, Max_Points => 16, Max_Nodes => 4);
      Big     : Work_Access;
      Status  : CSG.Outcome;
      Reason  : CSG.Reason_String;
      Last    : Natural;
      Ok      : Boolean;
      P, Q, N : CSG.Count;
   begin
      Primitives.Box (A, 2.0, 2.0, 2.0, Ok);
      Primitives.Box (B, 2.0, 2.0, 2.0, Ok);
      Transform.Translate (B, (1.0, 1.0, 1.0));

      CSG.Apply (CSG.Union, A, B, Result, Tiny, Check_W.all, Status, Reason, Last);
      Check ("csg kernel: a workspace too small says so and leaves Result empty",
             Status = CSG.Workspace_Full and Result.NT = 0 and Last > 0);

      CSG.Size_For (A.NT + B.NT, 1, P, Q, N);
      Big := new CSG.Workspace (P, Q, N);
      CSG.Apply (CSG.Union, A, B, Result, Big.all, Check_W.all, Status, Reason, Last);
      Check ("csg kernel: a sized workspace succeeds", Status = CSG.Success
             and Near (Volume (Result), 15.0) and Is_Watertight (Result));

      --  Forty times bigger: corners at 40 m, beyond the exact range.
      for I in 1 .. B.NV loop
         B.V (I) := B.V (I) * 40_000.0;
      end loop;
      CSG.Apply (CSG.Union, A, B, Result, Big.all, Check_W.all, Status, Reason, Last);
      Check ("csg kernel: coordinates beyond the exact range are refused",
             Status = CSG.Out_Of_Range and Result.NT = 0);

      A.NT := A.NT - 1;
      CSG.Apply (CSG.Union, A, B, Result, Big.all, Check_W.all, Status, Reason, Last);
      Check ("csg kernel: an open input is refused", Status = CSG.Input_Not_Solid
             and Result.NT = 0 and Reason (1 .. Last) = "first input is not a solid: 3 open edges");
   end Test_CSG_Kernel;

   --  Forge.Exact: the plane questions, answered without rounding.
   procedure Test_Exact is
      use Exact;
      --  A tilted plane through three points with fractional coordinates.
      A : constant Point := To_Point ((1.0, 2.0, 3.0));
      B : constant Point := To_Point ((9_999.5, 3.25, 7.0));
      C : constant Point := To_Point ((5.0, 8_888.125, 9.0));
      N : constant Vector := Cross (B - A, C - A);
      --  2B - C is exactly on it, 19.9 m out.
      On : constant Point := (2 * B.X - C.X, 2 * B.Y - C.Y, 2 * B.Z - C.Z);
      Up : constant Point := (On.X, On.Y, On.Z + 1);   --  one grid step higher
      Dn : constant Point := (On.X, On.Y, On.Z - 1);
      P  : constant Point := To_Point ((0.0, 0.0, 100.0));
      Q  : constant Point := To_Point ((0.0, 0.0, -100.0));
   begin
      Check ("exact: a point on a tilted plane is exactly on it", Side (N, A, On, 0) = 0);
      Check ("exact: one grid step (0.23 pm) above and below it is seen",
             Side (N, A, Up, 0) = -Side (N, A, Dn, 0) and Side (N, A, Up, 0) /= 0);
      Check ("exact: the side test agrees from every point of the plane",
             Side (N, A, Up, 0) = Side (N, B, Up, 0) and Side (N, B, Up, 0) = Side (N, C, Up, 0));
      Check ("exact: steps round trip", To_Vec3 (To_Point ((1.5, -2.25, 9_999.0)))
             = (1.5, -2.25, 9_999.0));
      Check ("exact: a crossing is the same point from either end",
             Crossing (N, A, P, Q) = Crossing (N, A, Q, P));
      Check ("exact: a crossing lands within a grid step of the plane",
             Side (N, A, Crossing (N, A, P, Q), L1 (N)) = 0);
   end Test_Exact;

   --  Booleans through the session. Volumes are checked by identities on
   --  the actual inputs (vol (A + B) + vol (A * B) = vol A + vol B, ...),
   --  since grid-rounded cylinders are not exactly the ideal polygon.
   procedure Test_CSG is
      package Elem is new Ada.Numerics.Generic_Elementary_Functions (Long_Float);
      S : Forge.Session.Session;
      R : Response;
      W : constant Check_Access :=
        new Validity.Workspace (Cap_V => 65_536, Cap_E => Validity.Edges_For (131_072));

      procedure Run (Line : String);
      function Vol (N : String) return Scalar;
      function Rep (N : String) return Validity.Report;
      function Says (Part : String) return Boolean;
      function Gon (Sides : Positive; Radius : Scalar) return Scalar;

      procedure Run (Line : String) is
      begin
         Execute (S, Line, R);
         if not R.Ok then
            Put_Line ("      unexpected: " & Line & " -> " & Image (R));
         end if;
      end Run;

      function Vol (N : String) return Scalar is
        (if Has_Solid (S, To_Name (N)) then Rep (N).Volume else -1.0);

      function Rep (N : String) return Validity.Report is
         Result : Validity.Report;
      begin
         if Has_Solid (S, To_Name (N)) then
            Validity.Inspect (Mesh_Of (S, To_Name (N)).all, W.all, Result);
         end if;
         return Result;
      end Rep;

      function Says (Part : String) return Boolean is
        (for some I in 1 .. R.Length - Part'Length + 1 =>
           R.Text (I .. I + Part'Length - 1) = Part);

      --  Area of a regular polygon inscribed in a circle (Long_Float oracle).
      function Gon (Sides : Positive; Radius : Scalar) return Scalar is
        (Scalar (Long_Float (Sides) / 2.0 * Long_Float (Radius) ** 2
                 * Elem.Sin (2.0 * Ada.Numerics.Pi / Long_Float (Sides))));

   begin
      --  [-1,1]^3 and [0,2]^3 overlap in [0,1]^3.
      Run ("box a 2 2 2");
      Run ("box b 2 2 2");
      Run ("translate b 1 1 1");
      Run ("union u a b");
      Run ("intersect i a b");
      Run ("difference d a b");
      Check ("csg: union of offset cubes = 8 + 8 - 1", Near (Vol ("u"), 15.0));
      Check ("csg: intersection = 1", Near (Vol ("i"), 1.0));
      Check ("csg: difference = 8 - 1", Near (Vol ("d"), 7.0));
      Check ("csg: all three are solids", Rep ("u").Solid and Rep ("i").Solid and Rep ("d").Solid);
      Check ("csg: fast check agrees with Is_Watertight on a result",
             Rep ("u").Watertight = Is_Watertight (Mesh_Of (S, To_Name ("u")).all));

      --  Faces that coincide exactly: the classic failure of booleans.
      Run ("box c 2 2 2");
      Run ("translate c 2 0 0");
      Run ("union ac a c");
      Check ("csg: cubes sharing a face fuse: one shell, volume 16, area 40",
             Rep ("ac").Shells = 1 and Near (Vol ("ac"), 16.0) and Near (Rep ("ac").Area, 40.0));
      Run ("box e 2 2 2");
      Run ("translate e 1 0 0");
      Run ("union ae a e");
      Check ("csg: four shared face planes give a clean 3 x 2 x 2 block",
             Near (Vol ("ae"), 12.0) and Near (Rep ("ae").Area, 32.0));

      --  Apart, inside, identical.
      Run ("box f 1 1 1");
      Run ("translate f 10 0 0");
      Run ("union af a f");
      Check ("csg: disjoint union keeps two shells",
             Rep ("af").Shells = 2 and Near (Vol ("af"), 9.0));
      declare
         H : constant Natural := History_Length (S);
      begin
         Execute (S, "intersect none a f", R);
         Check ("csg: disjoint intersection is an error and is not recorded",
                not R.Ok and History_Length (S) = H and Says ("empty"));
      end;
      Run ("box g 1 1 1");
      Run ("difference void a g");
      Check ("csg: a cube with a cube-shaped void inside: 2 shells, volume 7",
             Rep ("void").Solid and Rep ("void").Shells = 2 and Near (Vol ("void"), 7.0));
      Run ("union same a a");
      Check ("csg: A union A is A, triangle for triangle",
             Near (Vol ("same"), 8.0) and Mesh_Of (S, To_Name ("same")).NT = 12);

      --  A hole through a plate: genus 1, and the volume of the 32-gon.
      Run ("box plate 4 4 2");
      Run ("cylinder pin 1 4 32");
      Run ("difference drilled plate pin");
      Check ("csg: drilled plate is a solid of genus 1",
             Rep ("drilled").Solid and Rep ("drilled").Genus = 1);
      Check ("csg: drilled plate volume = plate - the half of the pin inside it",
             Near (Vol ("drilled"), Vol ("plate") - Vol ("pin") / 2));
      Check ("csg: and the pin is the 32-gon prism it should be, to 1e-8",
             Near (Vol ("pin"), 4.0 * Gon (32, 1.0), 1.0e-8));

      --  Oblique: nothing lines up, every cut is a rounded crossing.
      Run ("box o 2 2 2");
      Run ("rotate o z 30");
      Run ("rotate o x 20");
      Run ("translate o 0.3 0.2 0.1");
      Run ("union ao a o");
      Run ("intersect io a o");
      Run ("difference do a o");
      Check ("csg: oblique cubes, union + intersection = a + o",
             Near (Vol ("ao") + Vol ("io"), Vol ("a") + Vol ("o")));
      Check ("csg: oblique difference = a - intersection",
             Near (Vol ("do"), Vol ("a") - Vol ("io")));
      Check ("csg: oblique results are solids",
             Rep ("ao").Solid and Rep ("io").Solid and Rep ("do").Solid);

      --  Curved against curved.
      Run ("cylinder p 1 4 24");
      Run ("cylinder q 0.5 4 24");
      Run ("rotate q x 90");
      Run ("union pq p q");
      Run ("intersect ipq p q");
      Run ("difference dpq p q");
      Check ("csg: crossed pipes, union + intersection = both prisms",
             Near (Vol ("pq") + Vol ("ipq"), Vol ("p") + Vol ("q")));
      Check ("csg: pipe drilled across by a thinner pipe has genus 1",
             Rep ("dpq").Solid and Rep ("dpq").Genus = 1);

      --  What no closed mesh can hold is refused, with the reason.
      Run ("cylinder p2 1 4 24");
      Run ("rotate p2 x 90");
      declare
         H : constant Natural := History_Length (S);
      begin
         Execute (S, "difference pinched p p2", R);
         Check ("csg: equal pipes crossing touch at two points: refused",
                not R.Ok and Says ("pinches") and History_Length (S) = H);
         Run ("box k 2 2 2");
         Run ("translate k 2 2 2");
         Execute (S, "union bow a k", R);
         Check ("csg: cubes touching at a corner: refused as a nonmanifold vertex",
                not R.Ok and Says ("nonmanifold vertex"));
      end;

      --  In place, then undo, which replays every boolean from the text.
      declare
         Before : constant Scalar := Vol ("ao");
      begin
         Run ("difference a a g");
         Check ("csg: in place, a := a - g", Near (Vol ("a"), 7.0) and Rep ("a").Shells = 2);
         Run ("undo");
         Check ("csg: undo restores a", Near (Vol ("a"), 8.0));
         Check ("csg: replay is exact, bit for bit", Vol ("ao") = Before);
      end;

      --  The bracket from examples/: wall fused on, hole drilled through.
      Run ("box base 60 8 40");
      Run ("box wall 8 50 40");
      Run ("translate wall -26 29 0");
      Run ("cylinder hole 4 10 24");
      Run ("rotate hole x 90");
      Run ("translate hole 15 0 0");
      Run ("union body base wall");
      Run ("difference bracket body hole");
      Check ("csg: bracket is a solid with one through-hole",
             Rep ("bracket").Solid and Rep ("bracket").Genus = 1);
      Check ("csg: bracket volume = both boxes - the 8 mm of the hole inside the base",
             Near (Vol ("bracket"), 60.0 * 8.0 * 40.0 + 8.0 * 50.0 * 40.0 - Vol ("hole") * 8 / 10));

      --  A chain of booleans: six ribs one at a time, then a bore through
      --  the needles they left at their seams (guards Face_Planes).
      Run ("cylinder flange 40 10 64");
      Run ("cylinder hub 22 40 64");
      Run ("translate hub 0 0 15");
      Run ("union part flange hub");
      Run ("box rib 20 4 20");
      Run ("translate rib 28 0 14");
      Run ("rotate rib z 30");
      Run ("union part part rib");
      for I in 2 .. 6 loop
         Run ("rotate rib z 60");
         Run ("union part part rib");
      end loop;
      declare
         Ribbed : constant Scalar := Vol ("part");
      begin
         Run ("cylinder bore 14 80 64");
         Execute (S, "difference part part bore", R);
         Check ("csg: six ribs one at a time, then a bore, is a solid with one through-hole",
                R.Ok and then Rep ("part").Solid and then Rep ("part").Genus = 1);
         Check ("csg: the bore removes exactly its 64-gon over the 40 mm of hub",
                Near (Vol ("part"), Ribbed - Gon (64, 14.0) * 40));
      end;

      --  Then a keyway and bolt holes one at a time (guards the figure-8
      --  split in Fan).
      Run ("box key 6 6 80");
      Run ("translate key 14 0 15");
      Run ("difference part part key");
      Run ("cylinder bolt 4 20 24");
      Run ("translate bolt 30 0 0");
      Run ("difference part part bolt");
      for I in 2 .. 3 loop
         Run ("rotate bolt z 60");
         Execute (S, "difference part part bolt", R);
      end loop;
      Check ("csg: keyway and three bolt holes cut one at a time: a solid of genus 4",
             R.Ok and then Rep ("part").Solid and then Rep ("part").Genus = 4);
   end Test_CSG;

begin
   Test_Fixed;
   Test_Mesh;
   Test_Validity;
   Test_Primitives;
   Test_STL;
   Test_Commands;
   Test_Session;
   Test_Exact;
   Test_CSG_Kernel;
   Test_CSG;
   New_Line;
   if Failures = 0 then
      Put_Line ("all tests passed");
   else
      Put_Line (Failures'Image & " failure(s)");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Tests;
