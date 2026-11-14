
package Forge.UI is

   function Run_Command (Line : String) return String;

   function Solid_Count return Natural;

   function Solid_Name (Index : Positive) return String;

   function History_Count return Natural;

   function History_Line (Index : Positive) return String;

end Forge.UI;
