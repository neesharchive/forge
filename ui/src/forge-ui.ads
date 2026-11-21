
with Ada.Strings.Unbounded;

package Forge.UI is

   function Run_Command (Line : String) return String;

   function Run_Command
     (Line : String; Succeeded : out Boolean; Selection_Target : out Name)
      return String;
   --  Selection_Target is empty unless the command created or edited a named object.

   function Solid_Count return Natural;

   function Solid_Name (Index : Positive) return String;

   type Object_Properties (Found : Boolean := False) is record
      case Found is
         when True =>
            Shape, Validity : Ada.Strings.Unbounded.Unbounded_String;
            Dimensions, Position : Vec3;
            Scale, Volume : Scalar;
            Vertices, Triangles : Natural;
         when False =>
            null;
      end case;
   end record;

   function Object_Details (Object_Name : String) return Object_Properties;

   function History_Count return Natural;

   function History_Line (Index : Positive) return String;

   function Tree_Text (Include_Heading : Boolean := True) return String;
   --  Current document hierarchy, with siblings in operand order.

end Forge.UI;
