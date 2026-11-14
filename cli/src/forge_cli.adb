--  forge: the command-line front end.
--
--     forge_cli                 REPL on stdin, one response line per command
--     forge_cli part.forge      run a file, then keep reading stdin
--     forge_cli -c "box b 1 2 3" -c "info b"
--
--  This program contains no modeling logic. It reads lines, hands them
--  to Forge.Session.Execute, prints the response. That is the design:
--  the GUI is the same thing with a picture. An agent is the same thing
--  with a pipe.
--
--  Exit status is the number of failed commands, capped at 255, so a
--  script that goes wrong is visible to whatever ran it.

with Ada.Command_Line; use Ada.Command_Line;
with Ada.Text_IO;      use Ada.Text_IO;
with Forge.Session;    use Forge.Session;
with Forge;
with Forge.Mesh;       use Forge.Mesh;

procedure Forge_CLI is
   S        : Session;
   R        : Response;
   Failures : Natural := 0;
   I        : Positive := 1;

   procedure Show_Summary;
   procedure Show_Summary is
   begin
      Put_Line ("---  Forge Session ---");
      Put_Line ("Solids:" & Natural'Image (Solid_Count (S)));

      for J in 1 .. Solid_Count (S) loop
         declare
            N : constant Forge.Name := Solid_Name (S, J);
            M : constant Mesh_View := Mesh_Of (S, N);
            Lo, Hi : Forge.Vec3;
         begin
            Bounds (M.all, Lo, Hi);

            Put_Line (" " & Forge.Image (N));
            Put_Line ("   Vertices: " & Vertex_Index'Image (M.NV));
            Put_Line ("   Triangles: " & Triangle_Index'Image (M.NT));
            Put_Line ("   Volume: " & Forge.Scalar'Image (Volume (M.all)));
            Put_Line
               ("   Valid Solid: " &
                (if Is_Solid (M.all) then "Yes" else "No"));

            Put_Line
               ("  Min: (" &
                Forge.Scalar'Image (Lo.X) & ", " &
                Forge.Scalar'Image (Lo.Y) & ", " &
                Forge.Scalar'Image (Lo.Z) & ")");

            Put_Line
               ("  Max: (" &
                Forge.Scalar'Image (Hi.X) & ", " &
                Forge.Scalar'Image (Hi.Y) & ", " &
                Forge.Scalar'Image (Hi.Z) & ")");
         end;
      end loop;

      Put_Line ("History:" & Natural'Image (History_Length (S)));

      for J in 1 .. History_Length (S) loop
         Put_Line (" " & History_Line (S, J));
      end loop;

      Put_Line ("----------------------");
   end Show_Summary;

   procedure Run (Line : String);
   procedure Run (Line : String) is
   begin
      if Line = "summary" then
         Show_Summary;
         return;
      end if;

      Execute (S, Line, R);
      Put_Line (Image (R));
      if not R.Ok then
         Failures := Failures + 1;
      end if;
   end Run;

begin
   while I <= Argument_Count loop
      if Argument (I) = "-c" and then I < Argument_Count then
         Run (Argument (I + 1));
         I := I + 2;
      else
         Run ("load " & Argument (I));
         I := I + 1;
      end if;
   end loop;

   if Argument_Count = 0 or else (Argument_Count >= 1 and then Argument (1) /= "-c") then
      while not End_Of_File loop
         Run (Get_Line);
      end loop;
   end if;

   Set_Exit_Status (Exit_Status (Natural'Min (Failures, 255)));
end Forge_CLI;
