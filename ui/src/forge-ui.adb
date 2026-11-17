
with Forge.Session;
with Forge.Solid_Trees;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body Forge.UI is

   S : Forge.Session.Session;

   function Run_Command (Line : String) return String is
      R : Forge.Session.Response;
   begin
      Forge.Session.Execute (S, Line, R);
      return Forge.Session.Image (R);
   end Run_Command;

   function Solid_Count return Natural is
   begin
      return Forge.Session.Solid_Count (S);
   end Solid_Count;

   function Solid_Name (Index : Positive) return String is
   begin
      return Forge.Image (Forge.Session.Solid_Name (S, Index));
   end Solid_Name;

   function History_Count return Natural is
   begin
      return Forge.Session.History_Length (S);
   end History_Count;

   function History_Line (Index : Positive) return String is
   begin
      return Forge.Session.History_Line (S, Index);
   end History_Line;

   function Tree_Text return String is
      use Forge.Solid_Trees;
      Nodes : Node_Array := Forge.Session.View_Tree (S);
      Text : Unbounded_String := To_Unbounded_String ("CSG Tree:");
      procedure Children (Parent : Name; Depth : Natural);
      procedure Children (Parent : Name; Depth : Natural) is
      begin
         for N of Nodes loop
            if N.Kind /= World_Node and then N.Parent = Parent then
               Append (Text, ASCII.LF & String'(1 .. 2 * Depth => ' ') & Image (N.N)
                       & " (" & N.Kind'Image & ")"
                       & (if N.Kind in Union_Node .. Intersection_Node
                          then " geometry pending" else ""));
               Children (N.N, Depth + 1);
            end if;
         end loop;
      end Children;
   begin
      --  Stable ordering across the snapshot also orders each sibling set.
      for I in Nodes'First + 1 .. Nodes'Last loop
         declare
            Item : constant Node := Nodes (I);
            J : Natural := I;
         begin
            while J > Nodes'First and then Nodes (J - 1).Order > Item.Order loop
               Nodes (J) := Nodes (J - 1);
               J := J - 1;
            end loop;
            Nodes (J) := Item;
         end;
      end loop;
      Append (Text, ASCII.LF & "world");
      Children (World, 1);
      return To_String (Text);
   end Tree_Text;

end Forge.UI;
