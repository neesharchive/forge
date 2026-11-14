
with Forge.Session;

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

end Forge.UI;
