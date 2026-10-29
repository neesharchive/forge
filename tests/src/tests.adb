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
with Forge.Fixed;
with Forge.Grid;
with Forge.Text;
with Forge.Fixed_Geometry;
with Forge.Validation;
with Interfaces;

procedure Tests is

   Failures : Natural := 0;

   procedure Check (Name : String; Cond : Boolean);
   procedure Test_Mesh;
   procedure Test_Primitives;
   procedure Test_STL;
   procedure Test_Commands;
   procedure Test_Session;
   procedure Test_Booleans;
   procedure Test_Fixed;
   procedure Test_Validation;
   procedure Test_Production_Fixed;

   procedure Check (Name : String; Cond : Boolean) is
   begin
      Put_Line ((if Cond then "PASS  " else "FAIL  ") & Name);
      if not Cond then
         Failures := Failures + 1;
      end if;
   end Check;

   function Ratio (N, D : Integer) return Scalar is (Scalar (N) / Scalar (D));

   function Near (A, B : Scalar; Tol : Scalar := 16#0.00000004#) return Boolean is
     (abs (A - B) <= Tol * Scalar'Max (1.0, abs B));

   ---------------------------------------------------------------------

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
      Check ("tetra volume 1/6", Near (Volume (M), Ratio (1, 6)));

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
      Check ("cylinder volume approx pi*2", Near (Volume (M), Ratio (62_832, 10_000),
            Ratio (2, 1_000)));

      Transform.Translate (M, (5.0, 0.0, 0.0));
      Check ("translate keeps volume", Near (Volume (M), Ratio (62_832, 10_000),
            Ratio (2, 1_000)) and Is_Solid (M));
      Transform.Rotate (M, X, 90.0);
      Check ("rotate keeps solid", Is_Solid (M));
      Transform.Scale (M, 2.0);
      Check ("scale x2 gives x8 volume", Near (Volume (M), 8.0 * Ratio (62_832, 10_000),
            Ratio (2, 1_000)));
   end Test_Primitives;

   procedure Test_STL is
      use type STL.Byte;
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
      Check ("integer STL encoding of negative unit normal",
             Buf (93) = 0 and Buf (94) = 0 and Buf (95) = 128 and Buf (96) = 191);
      Check ("integer STL encoding of negative half coordinate",
             Buf (97) = 0 and Buf (98) = 0 and Buf (99) = 0 and Buf (100) = 191);
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
      Round_Trip ("setbox cut L 4 5 6");
      Round_Trip ("setcylinder cut R 2 8 24");
      Round_Trip ("settransform cut R translate 1 2 3");
      Round_Trip ("settransform cut R rotate z 31");
      Round_Trip ("settransform cut R scale 2");
      Round_Trip ("setop cut . difference");
      Round_Trip ("swap cut .");
      Round_Trip ("replace cut L k");

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
      Check ("csg expression created", R.Ok and History_Length (S) = 4);
      Execute (S, "evaluate u", R);
      Check ("csg evaluates", R.Ok);
      Execute (S, "undo", R);
      Check ("undo removes Boolean", R.Ok and History_Length (S) = 3);
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

   procedure Test_Booleans is
      S : Forge.Session.Session;
      R : Response;
      M : Mesh_View;
      procedure Run (Line : String);
      procedure Expect_Volume (N : String; V : Scalar);
      procedure Run (Line : String) is
      begin
         Execute (S, Line, R);
         Check (Line, R.Ok);
      end Run;
      procedure Expect_Volume (N : String; V : Scalar) is
      begin
         M := Mesh_Of (S, To_Name (N));
         Check (N & " validated mesh", M /= null);
         if M /= null then
            Check (N & " expected volume", Near (Volume (M.all), V));
         end if;
      end Expect_Volume;
   begin
      Run ("box a 2 2 2"); Run ("box b 2 2 2"); Run ("translate b 1 0 0");
      Run ("union u a b"); Expect_Volume ("u", 12.0);
      Run ("intersect i a b"); Expect_Volume ("i", 4.0);
      Run ("difference d a b"); Expect_Volume ("d", 4.0);
      Run ("difference e a a"); Expect_Volume ("e", 0.0);
      Run ("union ident a a"); Expect_Volume ("ident", 8.0);
      Run ("intersect ident_i a a"); Expect_Volume ("ident_i", 8.0);
      Run ("difference e2 e a"); Expect_Volume ("e2", 0.0);
      Run ("union fromempty e a"); Expect_Volume ("fromempty", 8.0);
      Run ("box far 2 2 2"); Run ("translate far 3 0 0");
      Run ("union disjoint a far"); Expect_Volume ("disjoint", 16.0);
      Run ("intersect disjoint_i a far"); Expect_Volume ("disjoint_i", 0.0);
      Run ("difference disjoint_d a far"); Expect_Volume ("disjoint_d", 8.0);
      Run ("box outer 4 4 4"); Run ("difference cavity outer a");
      Expect_Volume ("cavity", 56.0);
      Run ("box touch 2 2 2"); Run ("translate touch 2 0 0");
      Run ("union face a touch"); Expect_Volume ("face", 16.0);
      Run ("intersect face_i a touch"); Expect_Volume ("face_i", 0.0);
      Run ("translate touch 0 2 0"); Run ("union edge a touch");
      Execute (S, "evaluate edge", R);
      Check ("edge contact rejected", not R.Ok);
      Run ("undo"); Run ("redo");
      Check ("redo restores edge expression", Has_Solid (S, To_Name ("edge")));
      Run ("undo");
      Execute (S, "box bad 0 1 1", R);
      Check ("bad edit rejected", not R.Ok);
      Run ("redo");
      Check ("failed edit preserves redo", Has_Solid (S, To_Name ("edge")));
      Run ("undo"); Run ("box branch 1 1 1");
      Execute (S, "redo", R); Check ("new edit truncates redo", not R.Ok);
      Run ("setbox d L 4 2 2"); Expect_Volume ("d", 8.0);
      Expect_Volume ("a", 8.0);
      Run ("undo"); Expect_Volume ("d", 4.0);
      Run ("redo"); Expect_Volume ("d", 8.0);
      Execute (S, "replace d invalid a", R);
      Check ("invalid subtree edit rejected", not R.Ok);
      Expect_Volume ("d", 8.0);
   end Test_Booleans;

   procedure Test_Fixed is
      use Forge.Fixed;
      use Forge.Fixed_Geometry;
      use type Interfaces.Integer_64;
      P : Point := (1, 2, 3);
      Good : Boolean;
      Q : Interfaces.Integer_64;
      V : Tick;
      Hit : Point;
      A : constant Point := (1, 0, 0);
      B : constant Point := (0, 1, 0);
      C : constant Point := (1, 0, 1);
   begin
      Check ("fixed exact quarter turn", Quarter_Z (P) = (-2, 1, 3));
      Translate (P, (Tick'Last, 0, 0), Good);
      Check ("fixed overflow leaves input unchanged", not Good and then P = (1, 2, 3));
      Translate (P, (4, -2, 0), Good);
      Check ("fixed exact translation", Good and then P = (5, 0, 3));
      Divide_Rounded (5, 2, Q); Check ("fixed positive tie-even", Q = 2);
      Divide_Rounded (7, 2, Q); Check ("fixed positive odd tie", Q = 4);
      Divide_Rounded (-5, 2, Q); Check ("fixed negative tie-even", Q = -2);
      Divide_Rounded (-7, 2, Q); Check ("fixed negative odd tie", Q = -4);
      Parse_Decimal ("0.1", V, Good);
      Check ("fixed decimal parsed without binary float", Good and then V = 6554);
      Parse_Decimal ("10000.000000001", V, Good);
      Check ("fixed decimal range rejected", not Good);
      Check ("fixed exact plane classification", Classify (A, B, C, (0, 0, 0)) /= On_Plane);
      Split_Edge (A, B, C, (0, 0, 0), (2, 0, 0), Hit, Good);
      Check ("fixed representable split", Good and then Hit = (1, 0, 0));
      Split_Edge (A, B, C, (0, 0, 0), (1, 1, 0), Hit, Good);
      Check ("fixed unsafe off-grid split rejected", not Good);
   end Test_Fixed;

   procedure Test_Production_Fixed is
      use type Grid.Tick;
      use type Grid.Point;
      use type Interfaces.Unsigned_64;
      V : Scalar;
      Good, All_Good : Boolean;
      T, Saved : Grid.Tick;
      P : Grid.Point := (Grid.Tick'Last, 1, -1);
      Edges : constant array (1 .. 3) of Grid.Tick := [Grid.Tick'First, 0, Grid.Tick'Last];
      State : Interfaces.Unsigned_64 := 17;
      S, C : Scalar;
      Session : Forge.Session.Session;
      R : Response;
   begin
      Check ("production quantum is exactly 2^-48", Scalar'Small = Quantum);
      Text.Parse ("0.000000000000003552713678800500929355621337890625", V, Good);
      Check ("production parses one exact tick", Good and then V = Quantum);
      Check ("production tick formatting exact",
             Text.Number (Quantum) = "0.000000000000003552713678800500929355621337890625");
      Text.Parse ("0.0000000000000017763568394002504646778106689453125", V, Good);
      Check ("production half tick rounds to even zero", Good and then V = 0.0);
      Text.Parse ("0.0000000000000053290705182007513940334320068359375", V, Good);
      Check ("production odd half tick rounds up", Good and then V = 2 * Quantum);
      Text.Parse ("-0.0000000000000053290705182007513940334320068359375", V, Good);
      Check ("production negative tie rounds even", Good and then V = -2 * Quantum);
      Text.Parse ("10000.000000000000000000000000000000000000000000000001", V, Good);
      Check ("production rejects exact out-of-domain input", not Good);
      Text.Parse ("1e2", V, Good);
      Check ("production rejects unsupported exponent grammar", not Good);
      All_Good := True;
      for I in 1 .. 2_000 loop
         State := State * 6_364_136_223_846_793_005 + 1;
         T := Grid.Tick (State mod Interfaces.Unsigned_64 (Grid.Limit));
         if I mod 2 = 0 then
            T := -T;
         end if;
         Text.Parse (Text.Number (Grid.To_Scalar (T)), V, Good);
         All_Good := All_Good and then Good and then Grid.To_Tick (V) = T;
      end loop;
      Check ("2000 exact production decimal round trips", All_Good);
      for Edge of Edges loop
         Text.Parse (Text.Number (Grid.To_Scalar (Edge)), V, Good);
         Check ("production endpoint round trip", Good and then Grid.To_Tick (V) = Edge);
      end loop;
      Grid.Translate (P, (1, 0, 0), Good);
      Check ("production translation rejects overflow atomically",
             not Good and then P = (Grid.Tick'Last, 1, -1));
      for A in Axis loop
         declare
            Rotated : Grid.Point := P;
         begin
            for I in 1 .. 4 loop
               Rotated := Grid.Quarter_Turn (Rotated, A);
            end loop;
            Check ("four production quarter turns restore point", Rotated = P);
         end;
      end loop;
      for Sign in -1 .. 1 loop
         if Sign /= 0 then
            T := Grid.Tick (3 * Sign);
            Grid.Scale (T, Grid.Unit / 2, Good);
            Check ("production scale tie-even", Good and then T = Grid.Tick (2 * Sign));
         end if;
      end loop;
      T := Grid.Tick'Last; Saved := T;
      Grid.Scale (T, 2 * Grid.Unit, Good);
      Check ("production scaling overflow leaves value unchanged", not Good and then T = Saved);
      Sin_Cos (-270.0, S, C);
      Check ("production cardinal trigonometry exact", S = 1.0 and then C = 0.0);
      Sin_Cos (30.0, S, C);
      Check ("production noncardinal sine", abs (S - 0.5) < 64 * Quantum);
      Check ("production square root", abs (Sqrt (2.0) * Sqrt (2.0) - 2.0) < 8 * Quantum);
      Check ("production larger square root", abs (Sqrt (100_000_000.0) - 10_000.0) < 8 * Quantum);
      Check ("production tiny square root", Sqrt (Quantum) = Scalar (1) / 16_777_216);
      Check ("production atan quadrants", Atan2 (1.0, 1.0) > 0.0
             and then Atan2 (-1.0, -1.0) < -2.0);
      Execute (Session, "box b 20 20 20", R);
      Execute (Session, "cylinder cutter 6 30 32", R);
      Execute (Session, "difference cut b cutter", R);
      Execute (Session, "evaluate cut", R);
      Check ("production cube with cylindrical cut evaluates", R.Ok);
      Execute (Session, "box far 2 2 2", R);
      Execute (Session, "translate far 10000 0 0", R);
      Execute (Session, "evaluate far", R);
      Check ("production out-of-range transform fails evaluation", not R.Ok);
      Check ("failed fixed evaluation exposes no mesh", Mesh_Of (Session, To_Name ("far")) = null);
      Execute (Session, "bounds far", R);
      Check ("out-of-range symbolic bounds fail without exception", not R.Ok);
   end Test_Production_Fixed;

   procedure Test_Validation is
      use Forge.Validation;
      M : Tri_Mesh (32, 64);
      B : Tri_Mesh (16, 32);
      Good : Boolean;
      V : Vertex_Index;
      Result : Status;
      Shells : Natural;
   begin
      Forge.Primitives.Box (M, 2.0, 2.0, 2.0, Good);
      Forge.Validation.Check (M, Result, Shells);
      Tests.Check ("box full geometric validation", Result = Valid and Shells = 1);
      M.V (2) := M.V (1);
      Forge.Validation.Check (M, Result, Shells);
      Tests.Check ("collapsed triangle rejected", Result = Degenerate_Face);
      Forge.Primitives.Box (M, 2.0, 2.0, 2.0, Good);
      for I in 1 .. M.NT loop
         V := M.T (I).A; M.T (I).A := M.T (I).B; M.T (I).B := V;
      end loop;
      Forge.Validation.Check (M, Result, Shells);
      Tests.Check ("inward shell rejected", Result = Incorrect_Shell_Orientation);
      Forge.Primitives.Box (M, 2.0, 2.0, 2.0, Good);
      Forge.Primitives.Box (B, 2.0, 2.0, 2.0, Good);
      Forge.Transform.Translate (B, (0.5, 0.0, 0.0));
      for I in 1 .. B.NV loop
         Add_Vertex (M, B.V (I), V, Good);
      end loop;
      for I in 1 .. B.NT loop
         Add_Triangle (M, B.T (I).A + 8, B.T (I).B + 8, B.T (I).C + 8, Good);
      end loop;
      Tests.Check ("overlapping shells pass edge closure", Is_Watertight (M));
      Forge.Validation.Check (M, Result, Shells);
      Tests.Check ("overlapping shells rejected geometrically", Result = Self_Intersection);
   end Test_Validation;

begin
   Test_Mesh;
   Test_Primitives;
   Test_STL;
   Test_Commands;
   Test_Session;
   Test_Booleans;
   Test_Fixed;
   Test_Validation;
   Test_Production_Fixed;
   New_Line;
   if Failures = 0 then
      Put_Line ("all tests passed");
   else
      Put_Line (Failures'Image & " failure(s)");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Tests;
