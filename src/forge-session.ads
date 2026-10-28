--  Transactional replay document, independent model trees and lazy meshes.
--  Execute is the single mutation entry point. Successful modeling responses
--  describe edits, not mesh evaluation; evaluate/info/export request geometry.
--  Undo/redo retain a history prefix, failed edits preserve redo, and load is atomic.
--  Mesh_Of evaluates current geometry, returns null on failure and never returns
--  a stale prior mesh. Views expire on the next mutation of the session.
with Ada.Finalization;
with Forge.Model;
with Forge.History;
with Forge.Commands; use Forge.Commands;
with Forge.Mesh;     use Forge.Mesh;

with Bedrock.Responses;

package Forge.Session is

   Max_Solids  : constant := 64;
   Max_History : constant := Forge.History.Max_Count;

   type Session is new Ada.Finalization.Limited_Controlled with private;

   Max_Response : constant := 32_768;

   --  The GAP line protocol's reply, from bedrock: "ok", "ok <info>",
   --  or "err <reason>". Same type in framewise and yarlib's console.
   package Responses is new Bedrock.Responses (Max_Response);
   subtype Response is Responses.Response;
   function Image (R : Response) return String renames Responses.Image;

   procedure Execute (S : in out Session; Line : String; R : out Response);
   --  Atomically applies a modeling edit, query or document action.
   --  Export writes OBJ; failed loading preserves the previous document.

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
   --  Null on failed evaluation; valid until the next session mutation.

   function History_Length (S : Session) return Natural;
   function History_Line (S : Session; I : Positive) return String
     with Pre => I <= History_Length (S);
   --  The document, line by line. Save writes exactly these.

private
   Default_Cap_V : constant Vertex_Index := 65_536;
   Default_Cap_T : constant Triangle_Index := 131_072;
   type Mesh_Access is access Tri_Mesh;
   type Evaluation_State is (Not_Evaluated, Evaluated_Solid, Evaluated_Empty, Failed);
   type Solid is record
      Used : Boolean := False;
      N : Name;
      Root : Model.Node_Id := 0;
      M : Mesh_Access := null;
      Status : Evaluation_State := Not_Evaluated;
   end record;
   type Solid_Table is array (1 .. Max_Solids) of Solid;
   type State is record
      Solids : Solid_Table;
      Tree : Model.Tree;
   end record;
   type State_Access is access State;
   type History_Array is array (1 .. Max_History) of Command;
   type Session is new Ada.Finalization.Limited_Controlled with record
      Data : State_Access := null;
      History : History_Array;
      Cursor : Forge.History.Cursor;
   end record;
   overriding procedure Finalize (S : in out Session);
end Forge.Session;
