
with Forge.Commands;
with Forge.Mesh;
with Forge.Session;
with Forge.Solid_Trees;
with Forge.Validity;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body Forge.UI is

   S : Forge.Session.Session;
   type Workspace_Access is access Validity.Workspace;
   Inspector : Workspace_Access;

   function Run_Command (Line : String) return String is
      R : Forge.Session.Response;
   begin
      Forge.Session.Execute (S, Line, R);
      return Forge.Session.Image (R);
   end Run_Command;

   function Run_Command
     (Line : String; Succeeded : out Boolean; Selection_Target : out Name)
      return String
   is
      use Forge.Commands;

      R : Forge.Session.Response;
      C : Command;
      Parsed : Boolean;
      Error : Path_String;
   begin
      Forge.Session.Execute (S, Line, R);
      Succeeded := R.Ok;
      Selection_Target := (others => <>);

      --  A successful response means Execute accepted the input length and syntax.
      if Succeeded then
         Parse (Line, C, Parsed, Error);
         if Parsed then
            Selection_Target :=
              (case C.K is
                 when Box                     => C.Box_Name,
                 when Cube | Sphere           => C.Shape_Name,
                 when Cylinder                => C.Cyl_Name,
                 when Translate | Move        => C.Tr_Name,
                 when Rotate                  => C.Rot_Name,
                 when Scale | Resize          => C.Sc_Name,
                 when Boolean_Kind            => C.Result,
                 when Copy                    => C.Cp_Name,
                 when Delete | List | Info | Check | Tree_View | History_View
                    | Export | Undo | Redo | Save | Load | Comment | Empty =>
                    (others => <>));
         end if;
      end if;

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

   function Tree_Text (Include_Heading : Boolean := True) return String is
      use Forge.Solid_Trees;
      Nodes : Node_Array := Forge.Session.View_Tree (S);
      Text : Unbounded_String;
      procedure Children (Parent : Name; Depth : Natural);
      procedure Children (Parent : Name; Depth : Natural) is
      begin
         for N of Nodes loop
            if N.Kind /= World_Node and then N.Parent = Parent then
               Append (Text, ASCII.LF & String'(1 .. 2 * Depth => ' ') & Image (N.N)
                       & " (" & N.Kind'Image & ")");
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
      if Include_Heading then
         Append (Text, "CSG Tree:" & ASCII.LF);
      end if;
      Append (Text, "world");
      Children (World, 1);
      return To_String (Text);
   end Tree_Text;

   function Object_Details (Object_Name : String) return Object_Properties is
      use Forge.Solid_Trees;

      Nodes : constant Forge.Solid_Trees.Node_Array :=
         Forge.Session.View_Tree (S);
   begin
      for Item of Nodes loop
         if Item.Kind /= World_Node and then Forge.Image (Item.N) = Object_Name then
            declare
               M : constant Session.Mesh_View := Session.Mesh_Of (S, Item.N);
               Lo, Hi : Vec3;
               Report : Validity.Report;
               Shape : constant String :=
                 (case Item.Kind is
                    when Box_Node          => "Box",
                    when Cylinder_Node     => "Cylinder",
                    when Sphere_Node       => "Sphere",
                    when Union_Node        => "Union",
                    when Difference_Node   => "Difference",
                    when Intersection_Node => "Intersection",
                    when World_Node        => "");
            begin
               if Inspector = null then
                  Inspector := new Validity.Workspace
                    (M.Cap_V, Validity.Edges_For (M.Cap_T));
               end if;

               Mesh.Bounds (M.all, Lo, Hi);
               Validity.Inspect (M.all, Inspector.all, Report);

               return
                 (Found      => True,
                  Shape      => To_Unbounded_String (Shape),
                  Validity   => To_Unbounded_String
                    (if Report.Solid then "Valid solid"
                     else "Invalid solid (" & Validity.Problem (Report) & ")"),
                  Dimensions => Hi - Lo,
                  Position   => Item.Position,
                  Scale      => Item.Scale,
                  Volume     => Report.Volume,
                  Vertices   => Natural (M.NV),
                  Triangles  => Natural (M.NT));
            end;
         end if;
      end loop;

      return (Found => False);
   end Object_Details;

end Forge.UI;
