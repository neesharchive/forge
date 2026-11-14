--  The session: the single entry point for every front end.
--
--     Execute (S, "box base 40 20 10", Response)
--
--  That is the whole API. The CLI reads lines from stdin and calls it.
--  The GUI builds a line when you click and calls it. An agent calls
--  it. A .forge file is lines; Load calls it once per line. Nothing
--  above this package touches the kernel directly, so nothing above
--  this package can do what a script cannot.
--
--  State = named solids + history of modeling commands. The solids are
--  always what you get by replaying the history from empty; Undo pops
--  the history and replays. O(n) per undo, obviously correct, and it
--  keeps the invariant "the text is the model" literally true.
--
--  Memory: meshes are heap-allocated here, and only here. The kernel
--  (Forge.Mesh and below) never allocates; it computes on meshes it is
--  handed. This package is a desktop program's business.
--
--  Read-back for renderers is Mesh_Of: a constant view of a named
--  solid. A GUI draws that; it does not edit it.

with Forge.Commands; use Forge.Commands;
with Forge.Mesh;     use Forge.Mesh;
with Forge.Validity;

with Bedrock.Responses;

package Forge.Session is

   Max_Solids  : constant := 64;
   Max_History : constant := 4096;

   type Session is limited private;

   Max_Response : constant := 1024;

   --  The GAP line protocol's reply, from bedrock: "ok", "ok <info>",
   --  or "err <reason>". Same type in framewise and yarlib's console.
   package Responses is new Bedrock.Responses (Max_Response);
   subtype Response is Responses.Response;
   function Image (R : Response) return String renames Responses.Image;

   procedure Execute (S : in out Session; Line : String; R : out Response);
   --  Parses and runs one line. Modeling commands are appended to the
   --  history only if they succeed. Queries do not change state.
   --  Export writes a file; Save writes the history; Load replaces the
   --  session with the file's history (replayed, stopping at the first
   --  failing line, which is reported).

   ---------------------------------------------------------------------
   --  Read-back, for front ends
   ---------------------------------------------------------------------

   function Solid_Count (S : Session) return Natural;
   function Solid_Name (S : Session; I : Positive) return Name
     with Pre => I <= Solid_Count (S);
   function Has_Solid (S : Session; N : Name) return Boolean;

   type Mesh_View is access constant Tri_Mesh;
   function Mesh_Of (S : Session; N : Name) return Mesh_View
     with Pre => Has_Solid (S, N);
   --  Valid until the next Execute. Copy it if you need it longer.

   function History_Length (S : Session) return Natural;
   function History_Line (S : Session; I : Positive) return String
     with Pre => I <= History_Length (S);
   --  The document, line by line. Save writes exactly these.

private

   Default_Cap_V : constant Vertex_Index   := 65_536;
   Default_Cap_T : constant Triangle_Index := 131_072;
   --  Every solid gets this much room. Enough for a 256-segment
   --  cylinder squared. A boolean result that needs more reports it.

   type Mesh_Access is access Tri_Mesh;

   type Solid is record
      Used : Boolean := False;
      N    : Name;
      M    : Mesh_Access := null;
   end record;

   type Solid_Table is array (1 .. Max_Solids) of Solid;

   type History_Array is array (1 .. Max_History) of Command;

   type Check_Access is access Validity.Workspace;

   type Session is limited record
      Solids  : Solid_Table;
      History : History_Array;
      Count   : Natural := 0;          --  history length
      Scratch : Mesh_Access := null;   --  a boolean's result, before it is stored
      Checker : Check_Access := null;  --  validity workspace, room for any one solid
   end record;

end Forge.Session;
