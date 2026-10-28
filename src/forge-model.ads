--  Independent expression trees. Child IDs are internal, paths are public.
with Forge.Commands;
package Forge.Model with SPARK_Mode is
   Max_Nodes : constant := 4096;
   Max_Depth : constant := 128;
   subtype Node_Id is Natural range 0 .. Max_Nodes;
   type Node is record
      Payload : Commands.Command;
      Left, Right : Node_Id := 0;
   end record;
   type Node_Array is array (Node_Id range 1 .. Max_Nodes) of Node;
   type Tree is record
      Nodes : Node_Array;
      Used : Node_Id := 0;
   end record;
   procedure Add (T : in out Tree; C : Commands.Command; L, R : Node_Id;
                  Id : out Node_Id; Ok : out Boolean)
     with Pre => L <= T.Used and then R <= T.Used,
          Post => (if Ok then Id in 1 .. T.Used and then T.Used = T.Used'Old + 1
                   else Id = 0 and then T.Used = T.Used'Old);
   --  Adds a node only when there is capacity.
   procedure Clone (T : in out Tree; Root : Node_Id; Result : out Node_Id;
                    Ok : out Boolean);
   --  Copies an independent subtree; restores allocation count on failure.
   function Valid_Subtree (T : Tree; Root : Node_Id) return Boolean;
   --  Rejects invalid arity, cycles and paths exceeding the depth limit.
   function Resolve (T : Tree; Root : Node_Id; Path : String) return Node_Id;
   --  Resolves dot or L/R/C paths; zero means invalid path.
end Forge.Model;
