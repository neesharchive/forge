--  One document and one history for both text and typed commands.
--  Primitive meshes use the existing kernel. Boolean commands currently
--  group operands in the tree; Mesh_Of returns null for those placeholders.
--  Undo replays the active history; redo retains the undone suffix.

with Forge.Commands; use Forge.Commands;
with Forge.Mesh;     use Forge.Mesh;

with Forge.Solid_Trees; use Forge.Solid_Trees;
with Bedrock.Responses;
with Ada.Containers.Vectors;

package Forge.Session is

   Max_Solids  : constant := Solid_Trees.Max_Solids;
   Max_History : constant := 4096;

   type Session is limited private;

   Max_Response : constant := 8192;

   --  The GAP line protocol's reply, from bedrock: "ok", "ok <info>",
   --  or "err <reason>". Same type in framewise and yarlib's console.
   package Responses is new Bedrock.Responses (Max_Response);
   subtype Response is Responses.Response;
   function Image (R : Response) return String renames Responses.Image;

   procedure Execute (S : in out Session; Line : String; R : out Response);
   procedure Execute (S : in out Session; C : Command; R : out Response);
   --  Text and typed commands share validation, execution and history.
   --  Successful edits discard redo; failures restore the previous model.
   --  Seed save/load and named mesh export remain available.

   Invalid_Command : exception;
   function Make_Cube
     (S : in out Session; Length : Scalar;
      X, Y, Z : Scalar := 0.0; Scale : Scalar := 1.0) return Name;
   function Make_Sphere
     (S : in out Session; Radius : Scalar;
      X, Y, Z : Scalar := 0.0; Scale : Scalar := 1.0) return Name;
   --  Create a mesh and tree leaf, returning an automatically chosen name.
   procedure Delete_Shape (S : in out Session; Shape : Name);
   procedure Move_Shape (S : in out Session; Shape : Name; X, Y, Z : Scalar);
   procedure Scale_Shape (S : in out Session; Shape : Name; Scale : Scalar);
   --  Delete a subtree, set world position, or set scale about its position.
   --  Legacy translate/scale commands remain relative, about the world origin.
   function Union (S : in out Session; Shapes : Name_Array) return Name;
   function Subtraction (S : in out Session; Shapes : Name_Array) return Name;
   function Intersection (S : in out Session; Shapes : Name_Array) return Name;
   --  Group distinct siblings in supplied order; subtract later operands
   --  from the first. No Boolean geometry is evaluated at this stage.
   procedure Undo (S : in out Session);
   procedure Redo (S : in out Session);
   --  Typed conveniences raise Invalid_Command when Execute reports failure.
   procedure Export (S : Session; Filepath : String);
   --  Export top-level meshes as separate shells in one binary STL.
   --  Empty workspaces and pending Boolean groups raise Invalid_Command.
   --  No history or redo changes. Named export is available through Execute.

   type Command_Array is array (Positive range <>) of Command;
   function View_History
     (S : Session; Include_Redo : Boolean := False) return Command_Array;
   --  Detached commands, oldest first; History_Length is the active cursor.
   function View_Tree (S : Session) return Node_Array;
   --  Detached live nodes, World first. Join Parent to N, sort by Order.
   --  These typed queries return full data; text responses are bounded.

   ---------------------------------------------------------------------
   --  Read-back, for front ends
   ---------------------------------------------------------------------

   function Solid_Count (S : Session) return Natural;
   --  Number of tree objects, including Boolean groups and their operands.
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
   --  The active document, line by line, using Commands.Image.

private

   Default_Cap_V : constant Vertex_Index   := 65_536;
   Default_Cap_T : constant Triangle_Index := 131_072;
   --  Every solid gets this much room. Enough for a 256-segment
   --  cylinder squared. A boolean result that needs more reports it.

   type Mesh_Access is access Tri_Mesh;

   type Mesh_Table is array (1 .. Max_Solids) of Mesh_Access;
   package Histories is new Ada.Containers.Vectors (Positive, Command);
   --  History grows on the heap, up to Max_History; operand lists must
   --  not put several megabytes on the stack of every Session caller.

   type Session is limited record
      Tree    : Solid_Tree := [0 => (N => World, others => <>), others => <>];
      Meshes  : Mesh_Table := [others => null];
      History : Histories.Vector;
      Serial  : Positive := 1; --  generated names; not rewound by undo
      Count   : Natural := 0;   --  history length
   end record;

end Forge.Session;
