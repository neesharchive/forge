
pragma Ada_2022;

with Ada.Characters.Handling;
with Ada.Containers.Bounded_Vectors;
with Ada.Containers.Vectors;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Characters.Latin_1;
with Ada.Text_IO;

with Adi.SDL.Events;
with Adi.Font;
with Adi.App;
with Adi.Core;
with Adi.CSS_Styles;         use Adi.CSS_Styles;
with Adi.Layout_Util;
with Adi.MCP;
with Adi.Window;             use Adi.Window;
with Adi.Widget;             use Adi.Widget;
with Adi.Widget.Box;
with Adi.Widget.Button;
with Adi.Widget.Label;
with Adi.Widget.Text_Input;
with Adi.Widget_Styles;      use Adi.Widget_Styles;

with Forge.UI;
with Forge.Commands;

procedure Forge_GUI is

   --  Allow Adi2 widget handles to be converted to generic widget handles.
   use type Adi.Widget.Box.Box_Handle;
   use type Adi.Widget.Label.Label_Handle;
   use type Adi.Widget.Button.Button_Handle;
   use type Adi.Widget.Text_Input.Text_Input_Handle;

   package Object_Button_Vectors is new Ada.Containers.Vectors
     (Positive, Adi.Widget.Button.Button_Handle);
   type Display_Scalar is delta Forge.Scalar'Delta
     range Forge.Scalar'First .. Forge.Scalar'Last
     with Small => Forge.Scalar'Small, Size => Forge.Scalar'Size;
   package Scalar_IO is new Ada.Text_IO.Fixed_IO (Display_Scalar);

   type Property is (Dimensions, Position, Scale, Volume, Vertices, Triangles, Validity);

   --  Main application and window.
   A : Adi.App.App;
   W : Window_Handle;

   --  Stores the command entered by the user.
   Command_Text : Ada.Strings.Unbounded.Unbounded_String :=
     Ada.Strings.Unbounded.Null_Unbounded_String;

   package Recall_Vectors is new Ada.Containers.Bounded_Vectors
     (Positive, Ada.Strings.Unbounded.Unbounded_String, Ada.Strings.Unbounded."=");
   Recall_History : Recall_Vectors.Vector (Capacity => 100);
   Recall_Position : Natural := 0;
   Recall_Draft : Ada.Strings.Unbounded.Unbounded_String;

   --  Command words accepted by Forge.Commands.Parse, in display order.
   type Command_Word is
     (Box, Check, Copy, Cube, Cylinder, Delete, Difference, Export, History,
      Info, Intersect, List, Load, Move, Redo, Resize, Rotate, Save, Scale,
      Sphere, Translate, Tree, Undo, Union);
   Max_Suggestions : constant := 4;
   Command_Row : Adi.Widget.Box.Box_Handle;
   Suggestion_Viewport : Adi.Widget.Box.Box_Handle;
   Suggestion_Box : Adi.Widget.Box.Box_Handle;
   Suggestion_Buttons : array (1 .. Max_Suggestions) of Adi.Widget.Button.Button_Handle;
   Matches : array (1 .. Max_Suggestions) of Command_Word;
   Suggestion_Count : Natural range 0 .. Max_Suggestions := 0;
   Highlighted : Positive range 1 .. Max_Suggestions := 1;
   Suggestion_Geometry : Adi.Core.Rectangle := (others => 0.0);

   --  Track commands executed through the GUI.
   GUI_History : Ada.Strings.Unbounded.Unbounded_String :=
     Ada.Strings.Unbounded.Null_Unbounded_String;

   GUI_History_Count : Natural := 0;

   --  Labels used to display command results and model information.
   Result_Label : Adi.Widget.Label.Label_Handle;
   Result_Box : Adi.Widget.Box.Box_Handle;
   Result_Text_Box : Adi.Widget.Box.Box_Handle;
   Result_Outcome : Adi.Widget.Label.Label_Handle;
   Solids_Label : Adi.Widget.Label.Label_Handle;
   Object_Count_Label : Adi.Widget.Label.Label_Handle;
   History_Label : Adi.Widget.Label.Label_Handle;
   CSG_Label : Adi.Widget.Label.Label_Handle;
   No_Selection_Label : Adi.Widget.Label.Label_Handle;
   Object_Heading : Adi.Widget.Label.Label_Handle;
   Basic_Properties, Mesh_Properties : Adi.Widget.Box.Box_Handle;
   Property_Values : array (Property) of Adi.Widget.Label.Label_Handle;

   Object_Tabs : Adi.Widget.Box.Box_Handle;
   Object_Tabs_Viewport : Adi.Widget.Box.Box_Handle;
   Object_Buttons : Object_Button_Vectors.Vector;
   Selected_Name : Ada.Strings.Unbounded.Unbounded_String;

   --  Input field and label used for exporting a solid to STL.
   Export_Input : Adi.Widget.Text_Input.Text_Input_Handle;
   Export_Label : Adi.Widget.Label.Label_Handle;

   --  Tracks the main input field and controls the blinking cursor.
   Blink_Input : Adi.Widget.Text_Input.Text_Input_Handle :=
     Adi.Widget.Text_Input.Null_Text_Input_Handle;

   Blink_Time    : Duration := 0.0;
   Caret_Visible : Boolean := True;

   function Format_Number (Value : Forge.Scalar) return String;
   function Format_Vector (Value : Forge.Vec3) return String;
   procedure Add_Property_Group
     (Group : Adi.Widget.Box.Box_Handle; Heading : String; First, Last : Property);
   procedure Show_Selected_Object;
   procedure On_Object_Clicked (Widget : Widget_Handle);
   procedure Refresh_Object_Tabs (Count : Natural; Allow_Fallback : Boolean);

   procedure On_Caret_Tick (DT : Duration);
   function Word_Text (Word : Command_Word) return String;
   function Description (Word : Command_Word) return String;
   function Parameters (Word : Command_Word) return String;
   function Example (Word : Command_Word) return String;
   function Argument_Hint (Word : Command_Word; Arguments : String) return String;
   procedure Split_Command (Text : String; First, After_Word : out Positive);
   procedure Hide_Suggestions;
   procedure Position_Suggestions;
   procedure Update_Suggestions (Text : String);
   procedure Accept_Suggestion (Index : Positive);
   procedure On_Suggestion_Clicked (Widget : Widget_Handle);
   procedure Move_Suggestion (Down : Boolean);

   procedure On_Command_Changed
      (Widget : Widget_Handle;
      Text   : String);

   procedure On_Execute (Widget : Widget_Handle);
   procedure Execute_Command (Executed_Command : String; Clear_Input : Boolean);
   procedure Restore_Recall_Draft;
   procedure Navigate_Recall (Down : Boolean);

   procedure Show_Command_Result (Text : String; Succeeded : Boolean);
   procedure Style_Scrollbar (Widget : Widget_Handle);
   procedure Add_Section_Heading
     (Panel : Adi.Widget.Box.Box_Handle;
      Title : String;
      Trailing_Label : Adi.Widget.Label.Label_Handle := Adi.Widget.Label.Null_Label_Handle);

   procedure On_Export (Widget : Widget_Handle);

   procedure On_Window_Key
     (Scancode : Adi.SDL.Events.SDL_Scancode;
      Keycode  : Adi.SDL.Events.SDL_Keycode;
      Key_Mod  : Adi.SDL.Events.SDL_Keymod;
      Repeat   : Boolean;
      Handled  : in out Boolean);

   --  Sets the font size and text color for the GUI title.
   Title_Style : constant Style_Rules :=
     (Color     => Set (RGB (30, 35, 45)),
      Font_Size => Set_Font (Px (18.0)),
      others    => <>);

   Object_Heading_Style : constant Style_Rules :=
     (Title_Style with delta Font_Weight => Set (Weight_Semi_Bold));

   Brand_Style : constant Style_Rules :=
     (Object_Heading_Style with delta
      Font_Size => Set_Font (Px (28.0)), Font_Weight => Set (Weight_Bold));

   Subtitle_Style : constant Style_Rules :=
     (Color     => Set (RGB (86, 103, 124)),
      Font_Size => Set_Font (Px (13.0)),
      others    => <>);

   Heading_Row_Style : constant Style_Rules :=
     (Display        => Set (Flex),
      Flex_Direction => Set (Row),
      Align_Items    => Set (Align_Items_Value'(Center)),
      Flex_Shrink    => Set (0.0),
      Gap            => Set (Gap (Px (8.0))),
      others         => <>);

   Section_Heading_Style : constant Style_Rules :=
     (Object_Heading_Style with delta
      Font_Size      => Set_Font (Px (16.0)),
      Font_Weight    => Set (Weight_Bold),
      Text_Wrap_Mode => Set (TWM_Nowrap));

   Object_Count_Style : constant Style_Rules :=
     (Subtitle_Style with delta
      Color          => Set (RGB (95, 102, 110)),
      Text_Wrap_Mode => Set (TWM_Nowrap));

   Heading_Block_Style : constant Style_Rules :=
     (Display        => Set (Flex),
      Flex_Direction => Set (Column),
      Flex_Shrink    => Set (0.0),
      Gap            => Set (Gap (Px (4.0))),
      others         => <>);

   Heading_Accent_Style : constant Style_Rules :=
     (Width            => Set (Size (Px (28.0))),
      Height           => Set (Size (Px (2.0))),
      Align_Self       => Set (Align_Self_Value'(Flex_Start)),
      Flex_Shrink      => Set (0.0),
      Background_Color => Set_Bg (RGB (121, 163, 214)),
      Border_Radius    => Set (Radius (Px (1.0))),
      others           => <>);

   Property_Heading_Style : constant Style_Rules :=
     (Color       => Set (RGB (40, 70, 110)),
      Font_Size   => Set_Font (Px (13.0)),
      Font_Weight => Set (Weight_Semi_Bold),
      others      => <>);

   Scroll_Gutter : constant Opt_Margin_Sides :=
     Set_Margin (CSS_Box (Px (0.0), Px (10.0), Px (0.0), Px (0.0)));

   Property_Group_Style : constant Style_Rules :=
     (Display          => Set (Flex),
      Flex_Direction   => Set (Column),
      Flex_Shrink      => Set (0.0),
      Background_Color => Set_Bg (RGB (240, 243, 247)),
      Margin           => Scroll_Gutter,
      Padding          => Set (CSS_Box (Px (8.0))),
      Border_Radius    => Set (Radius (Px (6.0))),
      Gap              => Set (Gap (Px (4.0))),
      others           => <>);

   Property_Row_Style : constant Style_Rules :=
     (Display        => Set (Flex),
      Flex_Direction => Set (Row),
      Gap            => Set (Gap (Px (8.0))),
      others         => <>);

   Property_Key_Style : constant Style_Rules :=
     (Width       => Set (Size (Px (100.0))),
      Flex_Shrink => Set (0.0),
      others      => <>);

   --  Defines the appearance of the main command input field.
   Input_Style : constant Style_Rules :=
     (Background_Color => Set_Bg (RGB (255, 255, 255)),
      Padding          => Set (CSS_Box (Px (10.0))),
      Border_Radius    => Set (Radius (Px (6.0))),
      Flex_Grow        => Set (1.0),
      Flex_Basis       => Set (Basis (Px (0.0))),
      others           => <>);

   --  Gives the STL export input a contrasting background.
   Export_Input_Style : constant Style_Rules :=
     (Background_Color => Set_Bg (RGB (235, 239, 245)),
      Padding          => Set (CSS_Box (Px (10.0))),
      Border_Radius    => Set (Radius (Px (6.0))),
      others           => <>);

   --  Sets the background color, padding, and rounded corners for buttons.
   Button_Style : constant Style_Rules :=
     (Background_Color => Set_Bg (RGB (40, 100, 200)),
      Padding          => Set (CSS_Box (Px (12.0))),
      Border_Radius    => Set (Radius (Px (6.0))),
      others           => <>);

   --  Sets the button text color to white.
   Button_Text_Style : constant Style_Rules :=
     (Color  => Set (RGB (255, 255, 255)),
      others => <>);

   Object_Tabs_Style : constant Style_Rules :=
     (Display        => Set (Flex),
      Flex_Direction => Set (Row),
      Flex_Wrap      => Set (Wrap),
      Margin         => Scroll_Gutter,
      Gap            => Set (Gap (Px (6.0))),
      others         => <>);

   Object_Tabs_Viewport_Style : constant Style_Rules :=
     (Display        => Set (Flex),
      Flex_Direction => Set (Column),
      Height         => Set (Size (Px (40.0))),
      Flex_Shrink    => Set (0.0),
      Overflow_Y     => Set_Overflow_Y (Overflow_Auto),
      Overflow_X     => Set_Overflow_X (Overflow_Hidden),
      others         => <>);

   Object_Button_Style : constant Style_Rules :=
     (Button_Style with delta
      Background_Color => Set_Bg (RGB (235, 239, 245)),
      Padding          => Set (CSS_Box (Px (6.0))));

   --  Defines the visible text cursor using in the input fields.
   Cursor_Style : constant Style_Rules :=
     (Background_Color => Set_Bg (RGB (30, 35, 45)),
      others           => <>);

   --  Makes the cursor transparent during the blinking animation.
   Hidden_Cursor_Style : constant Style_Rules :=
     (Background_Color => Set_Bg (RGB (30, 35, 45)),
      Opacity          => Set (Opacity_Transparent),
      others           => <>);

   --  Arranges the main GUI elements vertically.
   Root_Style : constant Style_Rules :=
     (Display          => Set (Flex),
      Flex_Direction   => Set (Column),
      Background_Color => Set_Bg (RGB (235, 238, 242)),
      Padding          => Set (CSS_Box (Px (20.0))),
      Gap              => Set (Gap (Px (12.0))),
      others           => <>);

   --  Places the main panels side by side and fills available space.
   Panels_Style : constant Style_Rules :=
     (Display        => Set (Flex),
      Flex_Direction => Set (Row),
      Width          => Set (Size (Pct (100.0))),
      Min_Height     => Set (Size (Px (260.0))),
      Flex_Grow      => Set (1.0),
      Flex_Basis     => Set (Basis (Px (0.0))),
      Gap            => Set (Gap (Px (16.0))),
      others         => <>);

   --  Arranges the command input and Execute button horizontally.
   Command_Row_Style : constant Style_Rules :=
     (Display        => Set (Flex),
      Flex_Direction => Set (Row),
      Width          => Set (Size (Pct (100.0))),
      Gap            => Set (Gap (Px (12.0))),
      others         => <>);

   --  Keep the dropdown in the root's hit-test area and outside flex flow.
   Suggestion_Viewport_Style : constant Style_Rules :=
     (Position       => Set (Absolute),
      Display        => Set (Flex),
      Flex_Direction => Set (Column),
      Overflow_Y     => Set_Overflow_Y (Overflow_Auto),
      Overflow_X     => Set_Overflow_X (Overflow_Hidden),
      others         => <>);

   Suggestion_Box_Style : constant Style_Rules :=
     (Display          => Set (Flex),
      Flex_Direction   => Set (Column),
      Flex_Shrink      => Set (0.0),
      Padding          => Set (CSS_Box (Px (5.0), Px (11.0), Px (5.0), Px (5.0))),
      Gap              => Set (Gap (Px (2.0))),
      Background_Color => Set_Bg (RGB (228, 235, 243)),
      Border_Radius    => Set (Radius (Px (6.0))),
      others           => <>);

   Suggestion_Row_Style : constant Style_Rules :=
     (Background_Color => Set_Bg (RGB (255, 255, 255)),
      Padding          => Set (CSS_Box (Px (4.0), Px (7.0))),
      Border_Radius    => Set (Radius (Px (4.0))),
      Flex_Shrink      => Set (0.0),
      others           => <>);

   Suggestion_Selected_Style : constant Style_Rules :=
     (Background_Color => Set_Bg (RGB (205, 224, 247)), others => <>);

   Suggestion_Hover_Style : constant Style_Rules :=
     (Background_Color => Set_Bg (RGB (218, 232, 249)), others => <>);

   Suggestion_Text_Style : constant Style_Rules :=
     (Font_Size => Set_Font (Px (13.0)), others => <>);

   --  Shared styling for the main panels.
   Panel_Style : constant Style_Rules :=
     (Display          => Set (Flex),
      Flex_Direction   => Set (Column),
      Flex_Grow        => Set (1.0),
      Flex_Basis       => Set (Basis (Px (0.0))),
      Background_Color => Set_Bg (RGB (255, 255, 255)),
      Padding          => Set (CSS_Box (Px (12.0))),
      Gap              => Set (Gap (Px (12.0))),
      others           => <>);

   --  Divide the left column's height after its gap in a 2:3 ratio.
   Tree_Panel_Style : constant Style_Rules :=
     (Panel_Style with delta
      Flex_Grow  => Set (2.0),
      Overflow_Y => Set_Overflow_Y (Overflow_Hidden),
      Overflow_X => Set_Overflow_X (Overflow_Hidden));

   Selected_Panel_Style : constant Style_Rules :=
     (Panel_Style with delta
      Flex_Grow  => Set (3.0),
      Overflow_Y => Set_Overflow_Y (Overflow_Hidden),
      Overflow_X => Set_Overflow_X (Overflow_Hidden));

   --  Scroll the details independently of the title, count, and tabs.
   Selected_Details_Style : constant Style_Rules :=
     (Display        => Set (Flex),
      Flex_Direction => Set (Column),
      Flex_Grow      => Set (1.0),
      Flex_Basis     => Set (Basis (Px (0.0))),
      Overflow_Y     => Set_Overflow_Y (Overflow_Auto),
      Overflow_X     => Set_Overflow_X (Overflow_Hidden),
      Gap            => Set (Gap (Px (12.0))),
      others         => <>);

   --  Keep the status heading above a fixed area for scrolling responses.
   Result_Box_Style : constant Style_Rules :=
     (Display          => Set (Flex),
      Flex_Direction   => Set (Column),
      Height           => Set (Size (Px (140.0))),
      Flex_Shrink      => Set (0.0),
      Padding          => Set (CSS_Box (Px (8.0), Px (10.0))),
      Gap              => Set (Gap (Px (6.0))),
      Overflow_Y       => Set_Overflow_Y (Overflow_Hidden),
      Background_Color => Set_Bg (RGB (245, 247, 250)),
      Border_Radius    => Set (Radius (Px (6.0))),
      others           => <>);

   Result_Heading_Style : constant Style_Rules :=
     (Color       => Set (RGB (48, 68, 94)),
      Font_Weight => Set (Weight_Bold),
      others      => <>);

   Scroll_Track_Style : constant Style_Rules :=
     (Width            => Set (Size (Px (7.0))),
      Background_Color => Set_Bg (RGB (222, 228, 235)),
      Border_Radius    => Set (Radius (Px (4.0))),
      others           => <>);

   Scroll_Thumb_Style : constant Style_Rules :=
     (Width            => Set (Size (Px (5.0))),
      Min_Height       => Set (Size (Px (12.0))),
      Background_Color => Set_Bg (RGB (101, 119, 143)),
      Border_Radius    => Set (Radius (Px (3.0))),
      others           => <>);

   Scroll_Gutter_Style : constant Style_Rules :=
     (Margin => Scroll_Gutter, others => <>);

   --  Gives the two columns equal shares of the available width.
   Stack_Style : constant Style_Rules :=
     (Display        => Set (Flex),
      Flex_Direction => Set (Column),
      Flex_Grow      => Set (1.0),
      Flex_Basis     => Set (Basis (Px (0.0))),
      Min_Width      => Set (Size (Px (0.0))),
      Gap            => Set (Gap (Px (12.0))),
      others         => <>);

   --  Keeps the STL export panel compact.
   Export_Panel_Style : constant Style_Rules :=
     (Display          => Set (Flex),
      Flex_Direction   => Set (Column),
      Flex_Shrink      => Set (0.0),
      Background_Color => Set_Bg (RGB (255, 255, 255)),
      Padding          => Set (CSS_Box (Px (12.0))),
      Gap              => Set (Gap (Px (12.0))),
      others           => <>);

   --  Fills the history panel below its heading and scrolls the entries.
   History_Scroll_Style : constant Style_Rules :=
     (Display          => Set (Flex),
      Flex_Direction   => Set (Column),
      Flex_Grow        => Set (1.0),
      Flex_Basis       => Set (Basis (Px (0.0))),
      Background_Color => Set_Bg (RGB (240, 243, 247)),
      Overflow_Y       => Set_Overflow_Y (Overflow_Auto),
      Overflow_X       => Set_Overflow_X (Overflow_Hidden),
      Padding          => Set (CSS_Box (Px (6.0))),
      Border_Radius    => Set (Radius (Px (6.0))),
      others           => <>);

   function Format_Number (Value : Forge.Scalar) return String is
      Buffer : String (1 .. 64);
   begin
      Scalar_IO.Put (Buffer, Display_Scalar (Value), Aft => 2, Exp => 0);
      declare
         Text : constant String := Ada.Strings.Fixed.Trim (Buffer, Ada.Strings.Both);
      begin
         return (if Text = "-0.00" then "0.00" else Text);
      end;
   end Format_Number;

   function Format_Vector (Value : Forge.Vec3) return String is
     (Format_Number (Value.X) & ", " & Format_Number (Value.Y) & ", " & Format_Number (Value.Z));

   procedure Add_Property_Group
     (Group : Adi.Widget.Box.Box_Handle; Heading : String; First, Last : Property)
   is
      use Adi.Widget.Label;

      Title : constant Label_Handle := Create_Handle (Heading);
   begin
      Set_Part_Style (+Group, Main_Part,
                      Adi.Widget_Styles.Create.Base (Property_Group_Style).Build);
      Set_Part_Style (+Title, Label_Part,
                      Adi.Widget_Styles.Create.Base (Property_Heading_Style).Build);
      Add_Child (+Group, +Title);

      for Item in First .. Last loop
         declare
            Row_Box : constant Adi.Widget.Box.Box_Handle := Adi.Widget.Box.Create_Handle;
            Key : constant Label_Handle := Create_Handle
              (case Item is
                 when Dimensions => "Dimensions",
                 when Position   => "Position",
                 when Scale      => "Scale",
                 when Volume     => "Volume",
                 when Vertices   => "Vertices",
                 when Triangles  => "Triangles",
                 when Validity   => "Validity");
         begin
            Property_Values (Item) := Create_Handle ("");
            Set_Part_Style (+Row_Box, Main_Part,
                            Adi.Widget_Styles.Create.Base (Property_Row_Style).Build);
            Set_Part_Style (+Key, Main_Part,
                            Adi.Widget_Styles.Create.Base (Property_Key_Style).Build);
            Add_Child (+Row_Box, +Key);
            Add_Child (+Row_Box, +Property_Values (Item));
            Add_Child (+Group, +Row_Box);
         end;
      end loop;
   end Add_Property_Group;

   procedure Show_Selected_Object is
      use Ada.Strings.Unbounded;
      use Adi.Widget.Label;

      Name : constant String :=
        To_String (Selected_Name);
      Details : constant Forge.UI.Object_Properties := Forge.UI.Object_Details (Name);
   begin
      for Button of Object_Buttons loop
         Set_Selected (+Button, Adi.Widget.Button.Get_Text (Button) = Name);
      end loop;

      Set_Visible (+No_Selection_Label, not Details.Found);
      Set_Visible (+Object_Heading, Details.Found);
      Set_Visible (+Basic_Properties, Details.Found);
      Set_Visible (+Mesh_Properties, Details.Found);

      if Details.Found then
         Set_Text (Object_Heading, Name & "  /  " & To_String (Details.Shape));
         Set_Text (Property_Values (Dimensions), Format_Vector (Details.Dimensions));
         Set_Text (Property_Values (Position), Format_Vector (Details.Position));
         Set_Text (Property_Values (Scale), Format_Number (Details.Scale));
         Set_Text (Property_Values (Volume), Format_Number (Details.Volume));
         Set_Text (Property_Values (Vertices),
                   Ada.Strings.Fixed.Trim (Details.Vertices'Image, Ada.Strings.Both));
         Set_Text (Property_Values (Triangles),
                   Ada.Strings.Fixed.Trim (Details.Triangles'Image, Ada.Strings.Both));
         Set_Text (Property_Values (Validity), To_String (Details.Validity));
      end if;
   end Show_Selected_Object;

   procedure On_Object_Clicked (Widget : Widget_Handle) is
      Button : constant Adi.Widget.Button.Button_Handle :=
        Adi.Widget.Button.Try_As_Button (Widget);
   begin
      Selected_Name := Ada.Strings.Unbounded.To_Unbounded_String
        (Adi.Widget.Button.Get_Text (Button));
      Show_Selected_Object;
   end On_Object_Clicked;

   procedure Refresh_Object_Tabs (Count : Natural; Allow_Fallback : Boolean) is
      use Ada.Strings.Unbounded;
      use Adi.Widget.Button;

      Names : array (1 .. Count) of Unbounded_String;
      Selection_Exists : Boolean := False;
      Tabs_Changed : Boolean := Count /= Natural (Object_Buttons.Length);
   begin
      for I in Names'Range loop
         Names (I) := To_Unbounded_String (Forge.UI.Solid_Name (I));
         Selection_Exists := Selection_Exists or else Names (I) = Selected_Name;
         Tabs_Changed := Tabs_Changed or else Names (I) /= Get_Text (Object_Buttons (I));
      end loop;

      --  A failed load can leave a partial document. Refresh the tabs
      --  while keeping the stored selection until a command succeeds.
      if Allow_Fallback and then not Selection_Exists then
         Selected_Name := (if Count = 0 then Null_Unbounded_String else Names (1));
      end if;

      if Tabs_Changed then
         for Button of Object_Buttons loop
            declare
               Widget : Widget_Handle := +Button;
            begin
               Destroy (Widget);
            end;
         end loop;
         Object_Buttons.Clear;

         for Name of Names loop
            declare
               Button : constant Button_Handle := Create_Handle (To_String (Name));
            begin
               Set_Part_Style
                 (+Button, Main_Part,
                  Adi.Widget_Styles.Create.Base (Object_Button_Style)
                    .On_Selected ((Background_Color => Button_Style.Background_Color,
                                   others => <>)).Build);
               Set_Part_Style
                 (+Button, Label_Part,
                  Adi.Widget_Styles.Create.On_Selected (Button_Text_Style).Build);
               Connect_Clicked (Button, On_Object_Clicked'Unrestricted_Access);
               Add_Child (+Object_Tabs, +Button);
               Object_Buttons.Append (Button);
            end;
         end loop;
      end if;

      Set_Visible (+Object_Tabs_Viewport, Count > 0);
      Show_Selected_Object;
   end Refresh_Object_Tabs;

   function Word_Text (Word : Command_Word) return String is
     (Ada.Characters.Handling.To_Lower (Word'Image));

   function Description (Word : Command_Word) return String is
     (case Word is
         when Box        => "Create a rectangular box",
         when Check      => "Check mesh validity",
         when Copy       => "Duplicate an object",
         when Cube       => "Create a cube",
         when Cylinder   => "Create a cylinder (32 segments by default)",
         when Delete     => "Remove an object",
         when Difference => "Subtract objects",
         when Export     => "Write one object or the whole model to STL",
         when History    => "Show model history",
         when Info       => "Show object information",
         when Intersect  => "Keep shared volume",
         when List       => "List objects",
         when Load       => "Open a Forge document",
         when Move       => "Set absolute position",
         when Redo       => "Redo a modeling operation",
         when Resize     => "Set absolute scale",
         when Rotate     => "Rotate around an axis",
         when Save       => "Save a Forge document",
         when Scale      => "Multiply the current scale",
         when Sphere     => "Create a sphere",
         when Translate  => "Offset an object",
         when Tree       => "Show the CSG tree",
         when Undo       => "Undo a modeling operation",
         when Union      => "Combine objects");

   --  Angle brackets mark argument values. Square brackets mark optional groups.
   function Parameters (Word : Command_Word) return String is
     (case Word is
         when Box        => " <name> <width> <height> <depth>",
         when Cube       => " <name> <length> [<x> <y> <z> <scale>]",
         when Sphere     => " <name> <radius> [<x> <y> <z> <scale>]",
         when Cylinder   => " <name> <radius> <height> [<segments:3..256>]",
         when Move       => " <object> <x> <y> <z>",
         when Translate  => " <object> <dx> <dy> <dz>",
         when Rotate     => " <object> <x|y|z> <degrees>",
         when Scale      => " <object> <factor>",
         when Resize     => " <object> <scale>",
         when Union | Difference | Intersect =>
            " <result> <first> <second> [<more objects>...]",
         when Copy       => " <new-name> <source>",
         when Delete | Info | Check => " <object>",
         when Export     => " [<object>] <stl-file>",
         when Load | Save => " <forge-file>",
         when History | List | Redo | Tree | Undo => "");

   function Example (Word : Command_Word) return String is
     (case Word is
         when Box       => "box base 4 2 6",
         when Cube      => "cube block 2 0 0 3 1",
         when Sphere    => "sphere ball 2 0 0 3 1",
         when Translate => "translate base 2 0 0",
         when Rotate    => "rotate base z 90",
         when Export    => "export base base.stl",
         when others    => "");

   function Argument_Hint (Word : Command_Word; Arguments : String) return String is
      Position : Positive := 1;
      Between_Tokens : Boolean := True;
      Syntax : constant String := Parameters (Word);
      N : Natural := 0;
      Start : Natural := 0;
   begin
      if Syntax = "" then
         return "No arguments";
      end if;

      --  Track the token at the end of the field, where completion sets the caret.
      for Ch of Arguments loop
         if Ch = ' ' then
            if not Between_Tokens then
               Position := Position + 1;
            end if;
            Between_Tokens := True;
         else
            Between_Tokens := False;
         end if;
      end loop;

      if Word = Export then
         if Position = 1 then
            return "Argument 1: object name or STL file";
         elsif Position = 2 then
            return "Argument 2: STL file, when argument 1 names an object";
         end if;
      end if;

      for I in Syntax'Range loop
         if Syntax (I) = '<' then
            N := N + 1;
            Start := I;
         elsif Syntax (I) = '>' and then N = Position then
            return "Argument" & Positive'Image (Position) & ": " & Syntax (Start .. I);
         end if;
      end loop;

      if Word in Union | Difference | Intersect
        and then Position <= Forge.Commands.Max_Operands + 1
      then
         return "Argument" & Positive'Image (Position) & ": <more objects> (optional)";
      end if;
      return "";
   end Argument_Hint;

   procedure Split_Command (Text : String; First, After_Word : out Positive) is
   begin
      First := Text'First;
      while First <= Text'Last and then Text (First) = ' ' loop
         First := First + 1;
      end loop;

      After_Word := First;
      while After_Word <= Text'Last and then Text (After_Word) /= ' ' loop
         After_Word := After_Word + 1;
      end loop;
   end Split_Command;

   procedure Hide_Suggestions is
   begin
      Suggestion_Count := 0;
      Set_Visible (+Suggestion_Viewport, False);
   end Hide_Suggestions;

   procedure Position_Suggestions is
      use Adi.Core;

      Anchor : constant Rectangle := Geometry_In_Window (+Blink_Input);
      Row_Bounds : constant Rectangle := Geometry_In_Window (+Command_Row);
      Measured : constant Size_2D := Measure_At_Width (+Suggestion_Box, Anchor.Width);
      --  The command row spans the root's content width and ends at its
      --  bottom. Offset from those edges to align with the input field.
      Bounds : constant Rectangle :=
        (Anchor.X - Row_Bounds.X, Row_Bounds.Y + Row_Bounds.Height - Anchor.Y,
         Anchor.Width, Pixel_Type'Min (Measured.Height, Pixel_Type'Max (0.0, Anchor.Y)));
   begin
      if Bounds /= Suggestion_Geometry then
         Suggestion_Geometry := Bounds;
         Set_Part_Style
           (+Suggestion_Viewport, Main_Part,
            Adi.Widget_Styles.Create.Base
              ((Suggestion_Viewport_Style with delta
                Left   => Set_Left (Inset (Pix (Float (Bounds.X)))),
                Bottom => Set_Bottom (Inset (Pix (Float (Bounds.Y)))),
                Width  => Set (Size (Pix (Float (Bounds.Width)))),
                Height => Set (Size (Pix (Float (Bounds.Height)))))).Build);
      end if;
   end Position_Suggestions;

   procedure Update_Suggestions (Text : String) is
      First, After_Word : Positive;
   begin
      Split_Command (Text, First, After_Word);
      if First = After_Word then
         Hide_Suggestions;
         return;
      end if;

      declare
         Prefix : constant String :=
           Ada.Characters.Handling.To_Lower (Text (First .. After_Word - 1));
      begin
         Suggestion_Count := 0;
         for Word in Command_Word loop
            declare
               Name : constant String := Word_Text (Word);
            begin
               if Prefix'Length <= Name'Length and then Name (1 .. Prefix'Length) = Prefix then
                  declare
                     use Ada.Characters.Latin_1;
                     Exact : constant Boolean := Prefix = Name and then After_Word <= Text'Last;
                     Hint : constant String :=
                       (if Exact then Argument_Hint (Word, Text (After_Word .. Text'Last)) else "");
                     Sample : constant String := (if Exact then Example (Word) else "");
                  begin
                     Suggestion_Count := Suggestion_Count + 1;
                     Matches (Suggestion_Count) := Word;
                     Adi.Widget.Button.Set_Text
                       (Suggestion_Buttons (Suggestion_Count),
                        Name & Parameters (Word) & LF & Description (Word)
                        & (if Hint = "" then "" else LF & Hint)
                        & (if Sample = "" then "" else LF & "Example: " & Sample));
                  end;
                  exit when Suggestion_Count = Max_Suggestions;
               end if;
            end;
         end loop;
      end;

      Highlighted := 1;
      for I in Suggestion_Buttons'Range loop
         Set_Selected (+Suggestion_Buttons (I), I = Highlighted);
         Set_Visible (+Suggestion_Buttons (I), I <= Suggestion_Count);
      end loop;
      Set_Visible (+Suggestion_Viewport, Suggestion_Count > 0);
      if Suggestion_Count > 0 then
         Position_Suggestions;
      end if;
   end Update_Suggestions;

   procedure Move_Suggestion (Down : Boolean) is
   begin
      Set_Selected (+Suggestion_Buttons (Highlighted), False);
      if Down then
         Highlighted := (if Highlighted = Suggestion_Count then 1 else Highlighted + 1);
      else
         Highlighted := (if Highlighted = 1 then Suggestion_Count else Highlighted - 1);
      end if;
      Set_Selected (+Suggestion_Buttons (Highlighted), True);
   end Move_Suggestion;

   procedure Accept_Suggestion (Index : Positive) is
      use Ada.Strings.Unbounded;

      Text : constant String := To_String (Command_Text);
      First, After_Word : Positive;
   begin
      Split_Command (Text, First, After_Word);
      declare
         Completed : constant String :=
           Text (Text'First .. First - 1) & Word_Text (Matches (Index))
           & (if After_Word > Text'Last then " " else Text (After_Word .. Text'Last));
      begin
         if Completed /= Text then
            Adi.Widget.Text_Input.Set_Text (Blink_Input, Completed);
         end if;
         Command_Text := To_Unbounded_String (Completed);
         Set_Focus (W, +Blink_Input);
         Update_Suggestions (Completed);
      end;
   end Accept_Suggestion;

   procedure On_Suggestion_Clicked (Widget : Widget_Handle) is
   begin
      for I in 1 .. Suggestion_Count loop
         if Widget = Widget_Handle'(+Suggestion_Buttons (I)) then
            Accept_Suggestion (I);
            return;
         end if;
      end loop;
   end On_Suggestion_Clicked;

   --  Updates the stored command whenever the user types in the input field.
   --  The command is saved until the user presses Enter or clicks Execute.
   procedure On_Command_Changed
     (Widget : Widget_Handle;
      Text   : String)
   is
      pragma Unreferenced (Widget);
   begin
      Command_Text := Ada.Strings.Unbounded.To_Unbounded_String (Text);
      Update_Suggestions (Text);
   end On_Command_Changed;

   procedure Show_Command_Result (Text : String; Succeeded : Boolean) is
      Body_Style : constant Style_Rules :=
        (Result_Box_Style with delta Background_Color => Set_Bg
           (if Succeeded then RGB (232, 241, 251) else RGB (255, 243, 230)));
      Heading_Style : constant Style_Rules :=
        (Result_Heading_Style with delta Color => Set
           (if Succeeded then RGB (33, 83, 139) else RGB (151, 65, 27)));
   begin
      Set_Part_Style
        (+Result_Box, Main_Part, Adi.Widget_Styles.Create.Base (Body_Style).Build);
      Set_Part_Style
        (+Result_Outcome, Label_Part, Adi.Widget_Styles.Create.Base (Heading_Style).Build);
      Adi.Widget.Label.Set_Text (Result_Outcome, (if Succeeded then "Success" else "Error"));
      Set_Visible (+Result_Outcome, True);
      Adi.Widget.Label.Set_Text (Result_Label, Text);
      Set_Scroll_Offset_Y (+Result_Text_Box, 0.0);
   end Show_Command_Result;

   procedure Style_Scrollbar (Widget : Widget_Handle) is
   begin
      Set_Part_Style
        (Widget, Scroll_Part, Adi.Widget_Styles.Create.Base (Scroll_Track_Style).Build);
      Set_Part_Style
        (Widget, Knob_Part, Adi.Widget_Styles.Create.Base (Scroll_Thumb_Style).Build);
   end Style_Scrollbar;

   procedure Add_Section_Heading
     (Panel : Adi.Widget.Box.Box_Handle;
      Title : String;
      Trailing_Label : Adi.Widget.Label.Label_Handle := Adi.Widget.Label.Null_Label_Handle)
   is
      use Adi.Widget.Box;
      use Adi.Widget.Label;

      Heading : constant Box_Handle := Adi.Widget.Box.Create_Handle;
      Accent : constant Box_Handle := Adi.Widget.Box.Create_Handle;
      Title_Label : constant Label_Handle := Adi.Widget.Label.Create_Handle (Title);
   begin
      Set_Part_Style (+Heading, Main_Part,
                      Adi.Widget_Styles.Create.Base (Heading_Block_Style).Build);
      Set_Part_Style (+Accent, Main_Part,
                      Adi.Widget_Styles.Create.Base (Heading_Accent_Style).Build);
      Set_Part_Style (+Title_Label, Label_Part,
                      Adi.Widget_Styles.Create.Base (Section_Heading_Style).Build);

      if Trailing_Label = Null_Label_Handle then
         Add_Child (+Heading, +Title_Label);
      else
         declare
            Row_Box : constant Box_Handle := Adi.Widget.Box.Create_Handle;
            Row_Style : constant Style_Rules :=
              (Heading_Row_Style with delta
               Justify_Content => Set (Justify_Content_Value'(Space_Between)));
         begin
            Set_Part_Style (+Row_Box, Main_Part,
                            Adi.Widget_Styles.Create.Base (Row_Style).Build);
            Add_Child (+Row_Box, +Title_Label);
            Add_Child (+Row_Box, +Trailing_Label);
            Add_Child (+Heading, +Row_Box);
         end;
      end if;
      Add_Child (+Heading, +Accent);
      Add_Child (+Panel, +Heading);
   end Add_Section_Heading;

   procedure Restore_Recall_Draft is
      use Ada.Strings.Unbounded;
   begin
      Command_Text := Recall_Draft;
      Adi.Widget.Text_Input.Set_Text (Blink_Input, To_String (Command_Text));
      Recall_Position := 0;
      Recall_Draft := Null_Unbounded_String;
      Hide_Suggestions;
   end Restore_Recall_Draft;

   procedure Navigate_Recall (Down : Boolean) is
   begin
      if Down then
         if Recall_Position = Recall_History.Last_Index then
            Restore_Recall_Draft;
            return;
         end if;
         Recall_Position := Recall_Position + 1;
      elsif Recall_Position = 0 then
         Recall_Draft := Command_Text;
         Recall_Position := Recall_History.Last_Index;
      elsif Recall_Position > Recall_History.First_Index then
         Recall_Position := Recall_Position - 1;
      else
         return;
      end if;

      Command_Text := Recall_History (Recall_Position);
      --  A recalled command stays in history mode until the user edits it.
      Adi.Widget.Text_Input.Set_Text
        (Blink_Input, Ada.Strings.Unbounded.To_String (Command_Text));
   end Navigate_Recall;

   --  Sends the entered command to the Forge Library.
   --  Displays the result and updates the model information and history.
   procedure Execute_Command (Executed_Command : String; Clear_Input : Boolean) is
   begin
      declare
         Succeeded : Boolean;
         Selection_Target : Forge.Name;
         Result : constant String :=
           Forge.UI.Run_Command (Executed_Command, Succeeded, Selection_Target);

      begin
         Show_Command_Result (Result, Succeeded);

         --  Record nonempty commands in the GUI history.
         if Executed_Command'Length > 0 then
            if GUI_History_Count > 0 then
               Ada.Strings.Unbounded.Append
                 (GUI_History, Ada.Characters.Latin_1.LF);
            end if;

            GUI_History_Count := GUI_History_Count + 1;

            Ada.Strings.Unbounded.Append
              (GUI_History,
               Natural'Image (GUI_History_Count) & ". " &
               Executed_Command);
         end if;

         if Clear_Input then
            Adi.Widget.Text_Input.Set_Text (Blink_Input, "");
            Command_Text := Ada.Strings.Unbounded.Null_Unbounded_String;
            Recall_Position := 0;
            Recall_Draft := Ada.Strings.Unbounded.Null_Unbounded_String;
            Hide_Suggestions;
         end if;

         Adi.Widget.Label.Set_Text (CSG_Label, Forge.UI.Tree_Text (Include_Heading => False));

         declare
            Count : constant Natural := Forge.UI.Solid_Count;
            Names : Ada.Strings.Unbounded.Unbounded_String :=
              Ada.Strings.Unbounded.To_Unbounded_String ("Objects:");
         begin
            if Count = 0 then
               Ada.Strings.Unbounded.Append (Names, " (none)");
            else
               for I in 1 .. Count loop
                  if I > 1 then
                     Ada.Strings.Unbounded.Append (Names, ",");
                  end if;

                  Ada.Strings.Unbounded.Append
                    (Names, " " & Forge.UI.Solid_Name (I));
               end loop;
            end if;

            Adi.Widget.Label.Set_Text
              (Solids_Label, Ada.Strings.Unbounded.To_String (Names));

            Adi.Widget.Label.Set_Text
              (Object_Count_Label,
               Ada.Strings.Fixed.Trim (Natural'Image (Count), Ada.Strings.Left)
               & (if Count = 1 then " object" else " objects"));

            if Selection_Target.Length /= 0 then
               Selected_Name := Ada.Strings.Unbounded.To_Unbounded_String
                 (Forge.Image (Selection_Target));
            end if;

            Refresh_Object_Tabs (Count, Allow_Fallback => Succeeded);
         end;

         if GUI_History_Count > 0 then
            Adi.Widget.Label.Set_Text
              (History_Label, Ada.Strings.Unbounded.To_String (GUI_History));
         end if;
      end;
   end Execute_Command;

   procedure On_Execute (Widget : Widget_Handle) is
      pragma Unreferenced (Widget);
      use type Ada.Containers.Count_Type;
      use Ada.Strings.Unbounded;

      Text : constant String := To_String (Command_Text);
   begin
      if Ada.Strings.Fixed.Trim (Text, Ada.Strings.Both) /= ""
        and then (Recall_History.Is_Empty or else Recall_History.Last_Element /= Command_Text)
      then
         if Recall_History.Length = Recall_History.Capacity then
            Recall_History.Delete_First;
         end if;
         Recall_History.Append (Command_Text);
      end if;

      Execute_Command (Text, Clear_Input => True);
   end On_Execute;

   --  Gets the solid name from the export input field.
   --  Displays the generated export command in the main command field,
   --  then executes it through the existing command handler.
   procedure On_Export (Widget : Widget_Handle) is
      pragma Unreferenced (Widget);

      Name : constant String :=
        Adi.Widget.Text_Input.Get_Text (Export_Input);
   begin
      if Name'Length = 0 then
         Show_Command_Result ("Enter a solid name to export.", Succeeded => False);
      else
         declare
            Export_Command : constant String :=
              "export " & Name & " " & Name & ".stl";
         begin
            --  Update the stored command and visible command field.
            Command_Text :=
              Ada.Strings.Unbounded.To_Unbounded_String
                (Export_Command);

            Adi.Widget.Text_Input.Set_Text
              (Blink_Input, Export_Command);

            --  Execute the command and refresh the GUI information.
            Execute_Command (Export_Command, Clear_Input => True);
         end;
      end if;
   end On_Export;

   --  Consume geometry shortcuts before ADI2 dispatches to the focused widget.
   procedure On_Window_Key
     (Scancode : Adi.SDL.Events.SDL_Scancode;
      Keycode  : Adi.SDL.Events.SDL_Keycode;
      Key_Mod  : Adi.SDL.Events.SDL_Keymod;
      Repeat   : Boolean;
      Handled  : in out Boolean)
   is
      pragma Unreferenced (Keycode);
      use Adi.SDL.Events;

      Focus : constant Widget_Handle := Get_Focus_Handle (W);
      In_Command : constant Boolean := Focus = Widget_Handle'(+Blink_Input);
      In_Export : constant Boolean := Focus = Widget_Handle'(+Export_Input);
      Ctrl : constant Boolean := (Key_Mod and SDL_KMOD_CTRL) /= 0;
      Shift : constant Boolean := (Key_Mod and SDL_KMOD_SHIFT) /= 0;
   begin
      if Handled then
         return;
      end if;

      if Ctrl
        and then (Scancode = SDL_SCANCODE_Z or else (Scancode = SDL_SCANCODE_Y and not Shift))
      then
         --  Consume repeats too, so a held shortcut never reaches text undo.
         Handled := True;
         if not Repeat then
            Execute_Command
              ((if Scancode = SDL_SCANCODE_Z and then not Shift then "undo" else "redo"),
               Clear_Input => False);
         end if;
      elsif In_Command and then not Ctrl and then not Shift
        and then Scancode = SDL_SCANCODE_TAB
        and then (Suggestion_Count > 0 or else Repeat)
      then
         Handled := True;
         if not Repeat then
            Accept_Suggestion (Highlighted);
         end if;
      elsif In_Command and then not Ctrl
        and then Scancode = SDL_SCANCODE_ESCAPE and then Recall_Position /= 0
      then
         Handled := True;
         Restore_Recall_Draft;
      elsif In_Command and then Suggestion_Count > 0 and then not Ctrl
        and then Scancode in SDL_SCANCODE_UP | SDL_SCANCODE_DOWN | SDL_SCANCODE_ESCAPE
      then
         Handled := True;
         if Scancode = SDL_SCANCODE_ESCAPE then
            Hide_Suggestions;
         else
            Move_Suggestion (Down => Scancode = SDL_SCANCODE_DOWN);
         end if;
      elsif In_Command and then not Ctrl and then not Shift
        and then ((Scancode = SDL_SCANCODE_UP and then not Recall_History.Is_Empty)
                  or else (Scancode = SDL_SCANCODE_DOWN and then Recall_Position /= 0))
      then
         Handled := True;
         Navigate_Recall (Down => Scancode = SDL_SCANCODE_DOWN);
      elsif not Repeat and then Scancode = SDL_SCANCODE_RETURN then
         if In_Command then
            On_Execute (Focus);
            Handled := True;
         elsif In_Export then
            On_Export (Focus);
            Handled := True;
         end if;
      end if;
   end On_Window_Key;

   --  Controls the blinking text cursors in both input text fields.
   --  Uses the elapsed time to alternate the cursor styles
   --  between visible and transparent every half-second.
   procedure On_Caret_Tick (DT : Duration) is
   begin
      if Suggestion_Count > 0 then
         if Get_Focus_Handle (W) = Widget_Handle'(+Blink_Input)
           or else Has_State (+Suggestion_Viewport, State_Pressed)
           or else (for some Button of Suggestion_Buttons => Has_State (+Button, State_Pressed))
         then
            Position_Suggestions;
         else
            Hide_Suggestions;
         end if;
      end if;

      Blink_Time := Blink_Time + DT;

      if Blink_Time >= 0.5 then
         Blink_Time := Blink_Time - 0.5;
         Caret_Visible := not Caret_Visible;

         if Caret_Visible then
            Set_Part_Style
              (Widget_Handle'(+Blink_Input),
               Cursor_Part,
               Adi.Widget_Styles.Create.Base (Cursor_Style).Build);

            Set_Part_Style
              (Widget_Handle'(+Export_Input),
               Cursor_Part,
               Adi.Widget_Styles.Create.Base (Cursor_Style).Build);
         else
            Set_Part_Style
              (Widget_Handle'(+Blink_Input),
               Cursor_Part,
               Adi.Widget_Styles.Create.Base
                 (Hidden_Cursor_Style).Build);

            Set_Part_Style
              (Widget_Handle'(+Export_Input),
               Cursor_Part,
               Adi.Widget_Styles.Create.Base
                 (Hidden_Cursor_Style).Build);
         end if;
      end if;
   end On_Caret_Tick;

begin
   --  Initialize the Adi2 application before creating the window and widgets.
   A.Init;

   --  Find an available system font for the GUI.
   declare
      Family : Font_Handle := Adi.Font.Find ("Segoe UI");
   begin
      if Family = Null_Font then
         Family := Adi.Font.Find ("Arial");
      end if;

      if Family = Null_Font then
         Family := Adi.Font.Find ("DejaVu Sans");
      end if;

      if Family = Null_Font then
         Family := Adi.Font.Find ("Noto Sans");
      end if;

      if Family /= Null_Font then
         Adi.Font.Set_Default_Font (Family);
      end if;
   end;

   Adi.Layout_Util.Set_Px_Maps_To_Dip (True);
   A.Set_Target_FPS (60);

   --  Create the main Forge GUI window.
   W := Create_Window_Handle
     ("Forge - Geometry Demo",
      Adi.Window.Extent (Px (900.0), Px (680.0)));

   declare
      Result_Header : constant Adi.Widget.Box.Box_Handle := Adi.Widget.Box.Create_Handle;
      Result_Title : constant Adi.Widget.Label.Label_Handle :=
        Adi.Widget.Label.Create_Handle ("Command Status");

      --  Root container holds the command controls and both panels.
      Root : constant Adi.Widget.Box.Box_Handle :=
        Adi.Widget.Box.Create_Handle;

      --  Container that arranges the two columns horizontally.
      Panels : constant Adi.Widget.Box.Box_Handle :=
        Adi.Widget.Box.Create_Handle;

      --  Holds the command input and Execute button side by side.
      --  Left column displays the CSG tree and selected object.
      Left_Panel : constant Adi.Widget.Box.Box_Handle :=
        Adi.Widget.Box.Create_Handle;

      --  Separate container for the CSG tree and object list.
      Tree_Panel : constant Adi.Widget.Box.Box_Handle :=
         Adi.Widget.Box.Create_Handle;

      Tree_Body : constant Adi.Widget.Box.Box_Handle :=
        Adi.Widget.Box.Create_Handle;

      --  Right column displays command history and STL export controls.
      Right_Panel : constant Adi.Widget.Box.Box_Handle :=
        Adi.Widget.Box.Create_Handle;

      History_Panel : constant Adi.Widget.Box.Box_Handle :=
         Adi.Widget.Box.Create_Handle;

      --  Panel displaying information about the selected object.
      Selected_Panel : constant Adi.Widget.Box.Box_Handle :=
         Adi.Widget.Box.Create_Handle;

      Selected_Details : constant Adi.Widget.Box.Box_Handle :=
         Adi.Widget.Box.Create_Handle;

      --  Holds the command history in a scrollable area.
      History_Box : constant Adi.Widget.Box.Box_Handle :=
         Adi.Widget.Box.Create_Handle;

      --  Contains the STL export controls.
      Export_Panel : constant Adi.Widget.Box.Box_Handle :=
         Adi.Widget.Box.Create_Handle;

      Brand_Row : constant Adi.Widget.Box.Box_Handle := Adi.Widget.Box.Create_Handle;
      Title : constant Adi.Widget.Label.Label_Handle := Adi.Widget.Label.Create_Handle ("Forge");
      Subtitle : constant Adi.Widget.Label.Label_Handle :=
        Adi.Widget.Label.Create_Handle ("Geometry Library");

      Input : constant Adi.Widget.Text_Input.Text_Input_Handle :=
        Adi.Widget.Text_Input.Create_Handle ("");

      Execute_Button : constant Adi.Widget.Button.Button_Handle :=
        Adi.Widget.Button.Create_Handle ("Execute");

      Export_Button : constant Adi.Widget.Button.Button_Handle :=
        Adi.Widget.Button.Create_Handle ("Export STL");

   begin
      Blink_Input := Input;
      Command_Row := Adi.Widget.Box.Create_Handle;
      Result_Box := Adi.Widget.Box.Create_Handle;
      Result_Text_Box := Adi.Widget.Box.Create_Handle;
      Object_Tabs := Adi.Widget.Box.Create_Handle;
      Object_Tabs_Viewport := Adi.Widget.Box.Create_Handle;
      Set_Visible (+Object_Tabs_Viewport, False);
      CSG_Label := Adi.Widget.Label.Create_Handle (Forge.UI.Tree_Text (Include_Heading => False));

      --  Create the labels and input fields used to display
      --  model information and provide STL export controls.
      Result_Label :=
        Adi.Widget.Label.Create_Handle ("Enter a command to begin.");
      Result_Outcome := Adi.Widget.Label.Create_Handle ("");
      Set_Visible (+Result_Outcome, False);

      Solids_Label :=
        Adi.Widget.Label.Create_Handle ("Objects: (none)");

      History_Label :=
        Adi.Widget.Label.Create_Handle ("(none)");

      No_Selection_Label :=
         Adi.Widget.Label.Create_Handle ("No object selected.");
      Object_Heading := Adi.Widget.Label.Create_Handle ("");
      Basic_Properties := Adi.Widget.Box.Create_Handle;
      Mesh_Properties := Adi.Widget.Box.Create_Handle;

      Object_Count_Label :=
        Adi.Widget.Label.Create_Handle ("0 objects");

      Export_Label :=
        Adi.Widget.Label.Create_Handle ("Solid to export:");

      Export_Input :=
        Adi.Widget.Text_Input.Create_Handle ("");

      --  Apply the appearance and layout styles to the GUI widgets.
      Set_Part_Style
        (Widget_Handle'(+Root),
         Main_Part,
         Adi.Widget_Styles.Create.Base (Root_Style).Build);

      Set_Part_Style (+Brand_Row, Main_Part,
                      Adi.Widget_Styles.Create.Base (Heading_Row_Style).Build);
      Set_Part_Style (+Title, Label_Part,
                      Adi.Widget_Styles.Create.Base (Brand_Style).Build);
      Set_Part_Style (+Subtitle, Label_Part,
                      Adi.Widget_Styles.Create.Base (Subtitle_Style).Build);
      Add_Child (+Brand_Row, +Title);
      Add_Child (+Brand_Row, +Subtitle);

      Set_Part_Style
        (Widget_Handle'(+Input),
         Main_Part,
         Adi.Widget_Styles.Create.Base (Input_Style).Build);

      Set_Part_Style
        (Widget_Handle'(+Input),
         Cursor_Part,
         Adi.Widget_Styles.Create.Base (Cursor_Style).Build);

      --  Update the stored command whenever the user edits the input.
      Adi.Widget.Text_Input.Connect_Changed
        (Input, On_Command_Changed'Unrestricted_Access);

      Set_Part_Style
        (Widget_Handle'(+Execute_Button),
         Main_Part,
         Adi.Widget_Styles.Create.Base (Button_Style).Build);

      Set_Part_Style
        (Widget_Handle'(+Execute_Button),
         Label_Part,
         Adi.Widget_Styles.Create.Base (Button_Text_Style).Build);

      --  Connect the Execute button to the command execution procedure.
      Adi.Widget.Button.Connect_Clicked
        (Execute_Button, On_Execute'Unrestricted_Access);

      Set_Part_Style
        (Widget_Handle'(+Export_Button),
         Main_Part,
         Adi.Widget_Styles.Create.Base (Button_Style).Build);

      Set_Part_Style
        (Widget_Handle'(+Export_Button),
         Label_Part,
         Adi.Widget_Styles.Create.Base (Button_Text_Style).Build);

      --  Connect the Export STL button to the export procedure.
      Adi.Widget.Button.Connect_Clicked
        (Export_Button, On_Export'Unrestricted_Access);

      --  Add the application title above the main panels.
      Add_Child (+Root, +Brand_Row);

      Set_Part_Style
        (Widget_Handle'(+Export_Input),
         Main_Part,
         Adi.Widget_Styles.Create.Base (Export_Input_Style).Build);

      Set_Part_Style
        (Widget_Handle'(+Export_Input),
         Cursor_Part,
         Adi.Widget_Styles.Create.Base (Cursor_Style).Build);

      Set_Part_Style
        (Widget_Handle'(+Panels),
         Main_Part,
         Adi.Widget_Styles.Create.Base (Panels_Style).Build);

      --  Arrange the command input and Execute button horizontally.
      Set_Part_Style
         (Widget_Handle'(+Command_Row),
         Main_Part,
         Adi.Widget_Styles.Create.Base (Command_Row_Style).Build);

      --  Arrange the CSG Tree and Selected Object vertically.
      Set_Part_Style
         (Widget_Handle'(+Left_Panel),
            Main_Part,
            Adi.Widget_Styles.Create.Base (Stack_Style).Build);

      --  Style the CSG Tree as a separate panel.
      Set_Part_Style
         (Widget_Handle'(+Tree_Panel),
            Main_Part,
            Adi.Widget_Styles.Create.Base (Tree_Panel_Style).Build);
      Set_Part_Style (+Tree_Body, Main_Part,
                      Adi.Widget_Styles.Create.Base (Selected_Details_Style).Build);
      Style_Scrollbar (+Tree_Body);

      --  Arrange the right-side sections vertically.
      Set_Part_Style
         (Widget_Handle'(+Right_Panel),
          Main_Part,
          Adi.Widget_Styles.Create.Base (Stack_Style).Build);

      Set_Part_Style
         (Widget_Handle'(+History_Panel),
          Main_Part,
          Adi.Widget_Styles.Create.Base (Panel_Style).Build);

      --  Give command history its own scrollable area.
      Set_Part_Style
         (Widget_Handle'(+History_Box),
          Main_Part,
          Adi.Widget_Styles.Create.Base (History_Scroll_Style).Build);
      Style_Scrollbar (+History_Box);

      --  Style the separate STL export section.
      Set_Part_Style
         (Widget_Handle'(+Export_Panel),
          Main_Part,
          Adi.Widget_Styles.Create.Base (Export_Panel_Style).Build);

      --  Keep the CSG heading above the scrolling tree and object list.
      Add_Section_Heading (Tree_Panel, "CSG Tree");
      Add_Child (+Tree_Body, +CSG_Label);
      Add_Child (+Tree_Body, +Solids_Label);
      Add_Child (+Tree_Panel, +Tree_Body);

      --  Place the CSG Tree panel on the left.
      Add_Child (Widget_Handle'(+Left_Panel),
           Widget_Handle'(+Tree_Panel));

      --  Style the selected object panel.
      Set_Part_Style
        (Widget_Handle'(+Selected_Panel),
         Main_Part,
         Adi.Widget_Styles.Create.Base (Selected_Panel_Style).Build);

      --  Add the title and details to the panel.
      Set_Part_Style (+Object_Count_Label, Label_Part,
                      Adi.Widget_Styles.Create.Base (Object_Count_Style).Build);
      Add_Section_Heading (Selected_Panel, "Selected Object", Object_Count_Label);

      Set_Part_Style
        (+Object_Tabs, Main_Part,
         Adi.Widget_Styles.Create.Base (Object_Tabs_Style).Build);
      Set_Part_Style
        (+Object_Tabs_Viewport, Main_Part,
         Adi.Widget_Styles.Create.Base (Object_Tabs_Viewport_Style).Build);
      Style_Scrollbar (+Object_Tabs_Viewport);
      Add_Child (+Object_Tabs_Viewport, +Object_Tabs);
      Add_Child (+Selected_Panel, +Object_Tabs_Viewport);

      Set_Part_Style
        (+Object_Heading, Label_Part,
         Adi.Widget_Styles.Create.Base (Object_Heading_Style).Build);
      Add_Property_Group (Basic_Properties, "Properties", Dimensions, Scale);
      Add_Property_Group (Mesh_Properties, "Mesh Geometry", Volume, Validity);
      Set_Part_Style
        (+Selected_Details, Main_Part,
         Adi.Widget_Styles.Create.Base (Selected_Details_Style).Build);
      Style_Scrollbar (+Selected_Details);
      Add_Child (+Selected_Details, +No_Selection_Label);
      Add_Child (+Selected_Details, +Object_Heading);
      Add_Child (+Selected_Details, +Basic_Properties);
      Add_Child (+Selected_Details, +Mesh_Properties);
      Add_Child (+Selected_Panel, +Selected_Details);
      Show_Selected_Object;

      --  Position the selected object below the CSG tree.
      Add_Child (Widget_Handle'(+Left_Panel),
               Widget_Handle'(+Selected_Panel));

      --  Place command history inside its scrollable container.
      Add_Child (Widget_Handle'(+History_Box),
                 Widget_Handle'(+History_Label));

      Add_Section_Heading (History_Panel, "Command History");

      Add_Child (Widget_Handle'(+History_Panel),
                 Widget_Handle'(+History_Box));

      --  Keep the STL export controls in their own section.
      Add_Section_Heading (Export_Panel, "Export STL");
      Add_Child (Widget_Handle'(+Export_Panel),
                 Widget_Handle'(+Export_Label));

      Add_Child (Widget_Handle'(+Export_Panel),
                 Widget_Handle'(+Export_Input));

      Add_Child (Widget_Handle'(+Export_Panel),
                 Widget_Handle'(+Export_Button));

      --  Stack command history and export on the right.
      Add_Child (Widget_Handle'(+Right_Panel),
                 Widget_Handle'(+History_Panel));

      Add_Child (Widget_Handle'(+Right_Panel),
                 Widget_Handle'(+Export_Panel));

      --  Combine both panels and attach them to the main layout.
      Add_Child (Widget_Handle'(+Panels),
                 Widget_Handle'(+Left_Panel));

      Add_Child (Widget_Handle'(+Panels),
                 Widget_Handle'(+Right_Panel));

      Add_Child (Widget_Handle'(+Root),
                 Widget_Handle'(+Panels));

      --  Display the command result above the command bar.
      Set_Part_Style
        (+Result_Box, Main_Part, Adi.Widget_Styles.Create.Base (Result_Box_Style).Build);
      Set_Part_Style
        (+Result_Text_Box, Main_Part,
         Adi.Widget_Styles.Create.Base (Selected_Details_Style).Build);
      Set_Part_Style
        (+Result_Header, Main_Part,
         Adi.Widget_Styles.Create.Base (Heading_Row_Style).Build);
      Set_Part_Style
        (+Result_Title, Label_Part,
         Adi.Widget_Styles.Create.Base (Result_Heading_Style).Build);
      Style_Scrollbar (+Result_Text_Box);
      Add_Child (+Result_Text_Box, +Result_Label);
      Add_Child (+Result_Header, +Result_Title);
      Add_Child (+Result_Header, +Result_Outcome);
      Add_Child (+Result_Box, +Result_Header);
      Add_Child (+Result_Box, +Result_Text_Box);
      Add_Child (+Root, +Result_Box);

      --  The built-in scrollbar overlays the viewport; keep text clear of it.
      declare
         Labels : constant array (Positive range <>) of Adi.Widget.Label.Label_Handle :=
           [CSG_Label, Solids_Label, Object_Heading, No_Selection_Label,
            History_Label, Result_Label];
      begin
         for Label of Labels loop
            Set_Part_Style
              (+Label, Main_Part, Adi.Widget_Styles.Create.Base (Scroll_Gutter_Style).Build);
         end loop;
      end;

      --  Place the command input and Execute button side by side.
      Add_Child (Widget_Handle'(+Command_Row),
                 Widget_Handle'(+Input));

      Add_Child (Widget_Handle'(+Command_Row),
                 Widget_Handle'(+Execute_Button));

      --  Position the completed command bar below the panels.
      Add_Child (+Root, +Command_Row);

      --  ADI2 hit-tests a child only inside its parent, so attach the popup to the root.
      Suggestion_Viewport := Adi.Widget.Box.Create_Handle;
      Suggestion_Box := Adi.Widget.Box.Create_Handle;
      Set_Part_Style
        (+Suggestion_Box, Main_Part,
         Adi.Widget_Styles.Create.Base (Suggestion_Box_Style).Build);
      Set_Visible (+Suggestion_Viewport, False);
      Style_Scrollbar (+Suggestion_Viewport);
      for Button of Suggestion_Buttons loop
         Button := Adi.Widget.Button.Create_Handle ("");
         --  Keep suggestion rows out of Tab traversal.
         Set_Focusable (+Button, False);
         Set_Part_Style
           (+Button, Main_Part,
            Adi.Widget_Styles.Create.Base (Suggestion_Row_Style)
              .On_Hover (Suggestion_Hover_Style)
              .On_Selected (Suggestion_Selected_Style).Build);
         Set_Part_Style
           (+Button, Label_Part,
            Adi.Widget_Styles.Create.Base (Suggestion_Text_Style).Build);
         Adi.Widget.Button.Connect_Clicked (Button, On_Suggestion_Clicked'Unrestricted_Access);
         Add_Child (+Suggestion_Box, +Button);
      end loop;
      Add_Child (+Suggestion_Viewport, +Suggestion_Box);
      Add_Child (+Root, +Suggestion_Viewport);

      --  Attach the completed layout to the window and place
      --  keyboard focus in the main command field.
      Set_Root (W, Widget_Handle'(+Root));
      Adi.Window.Set_Focus (W, Widget_Handle'(+Input));
   end;

   Adi.MCP.Initialize (W);

   Adi.Widget.Set_Debug_Layout_Overlay_Enabled (False);

   --  Register the window, Enter-key handler, and cursor animation
   --  callback before starting the application.
   A.Add_Window (W);
   Connect_Key_Down (W, On_Window_Key'Unrestricted_Access);
   Connect_Tick (W, On_Caret_Tick'Unrestricted_Access);
   A.Run;
   Adi.MCP.Finalize;

end Forge_GUI;
