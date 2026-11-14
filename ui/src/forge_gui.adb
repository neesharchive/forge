
pragma Ada_2022;

with Ada.Strings.Unbounded;
with Ada.Characters.Latin_1;

with Adi.SDL.Events;
with Adi.Font;
with Adi.App;
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

procedure Forge_GUI is

   --  Allow Adi2 widget handles to be converted to generic widget handles.
   use type Adi.Widget.Box.Box_Handle;
   use type Adi.Widget.Label.Label_Handle;
   use type Adi.Widget.Button.Button_Handle;
   use type Adi.Widget.Text_Input.Text_Input_Handle;

   --  Main application and window.
   A : Adi.App.App;
   W : Window_Handle;

   --  Stores the command entered by the user.
   Command_Text : Ada.Strings.Unbounded.Unbounded_String :=
     Ada.Strings.Unbounded.Null_Unbounded_String;

   --  Labels used to display command results and model information.
   Result_Label : Adi.Widget.Label.Label_Handle;
   Solids_Label : Adi.Widget.Label.Label_Handle;
   Status_Label : Adi.Widget.Label.Label_Handle;
   History_Label : Adi.Widget.Label.Label_Handle;

   --  Input field and label used for exporting a solid to STL.
   Export_Input : Adi.Widget.Text_Input.Text_Input_Handle;
   Export_Label : Adi.Widget.Label.Label_Handle;

   --  Tracks the main input field and controls the blinking cursor.
   Blink_Input : Adi.Widget.Text_Input.Text_Input_Handle :=
     Adi.Widget.Text_Input.Null_Text_Input_Handle;

   Blink_Time    : Duration := 0.0;
   Caret_Visible : Boolean := True;

   procedure On_Caret_Tick (DT : Duration);

   procedure On_Command_Changed
      (Widget : Widget_Handle;
      Text   : String);

   procedure On_Execute (Widget : Widget_Handle);

   procedure On_Export (Widget : Widget_Handle);

   procedure On_Enter_Key
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
      Flex_Grow      => Set (1.0),
      Gap            => Set (Gap (Px (16.0))),
      others         => <>);

   --  Arranges the command input and Execute button horizontally.
   Command_Row_Style : constant Style_Rules :=
     (Display        => Set (Flex),
      Flex_Direction => Set (Row),
      Width          => Set (Size (Pct (100.0))),
      Gap            => Set (Gap (Px (12.0))),
      others         => <>);

   --  Sets the shared appearance and sizing of both panels.
   Panel_Style : constant Style_Rules :=
     (Display          => Set (Flex),
      Flex_Direction   => Set (Column),
      Flex_Grow        => Set (1.0),
      Flex_Basis       => Set (Basis (Px (0.0))),
      Background_Color => Set_Bg (RGB (255, 255, 255)),
      Padding          => Set (CSS_Box (Px (12.0))),
      Gap              => Set (Gap (Px (12.0))),
      others           => <>);

   --  Stacks the information and export panels vertically.
   Right_Stack_Style : constant Style_Rules :=
     (Display        => Set (Flex),
      Flex_Direction => Set (Column),
      Flex_Grow      => Set (1.0),
      Flex_Basis     => Set (Basis (Px (0.0))),
      Gap            => Set (Gap (Px (12.0))),
      others         => <>);

   --  Keeps the STL export panel compact.
   Export_Panel_Style : constant Style_Rules :=
     (Display          => Set (Flex),
      Flex_Direction   => Set (Column),
      Background_Color => Set_Bg (RGB (255, 255, 255)),
      Padding          => Set (CSS_Box (Px (12.0))),
      Gap              => Set (Gap (Px (12.0))),
      others           => <>);

   --  Keeps command history at a fixed height with vertical scrolling.
   History_Scroll_Style : constant Style_Rules :=
     (Height       => Set (Size (Px (140.0))),
      Background_Color => Set_Bg (RGB (240, 243, 247)),
      Overflow_Y   => Set_Overflow_Y (Overflow_Auto),
      Overflow_X   => Set_Overflow_X (Overflow_Hidden),
      Padding      => Set (CSS_Box (Px (6.0))),
      Border_Radius => Set (Radius (Px (6.0))),
      others       => <>);

   --  Updates the stored command whenever the user types in the input field.
   --  The command is saved until the user presses Enter or clicks Execute.
   procedure On_Command_Changed
     (Widget : Widget_Handle;
      Text   : String)
   is
      pragma Unreferenced (Widget);
   begin
      Command_Text := Ada.Strings.Unbounded.To_Unbounded_String (Text);
   end On_Command_Changed;

   --  Sends the entered command to the Forge Library.
   --  Displays the result and updates the solids list,
   --  command history, and geometry status.
   procedure On_Execute (Widget : Widget_Handle) is
      pragma Unreferenced (Widget);
   begin
      declare
         Result : constant String :=
           Forge.UI.Run_Command
             (Ada.Strings.Unbounded.To_String (Command_Text));

      begin
         Adi.Widget.Label.Set_Text (Result_Label, Result);

         declare
            Count : constant Natural := Forge.UI.Solid_Count;
            Names : Ada.Strings.Unbounded.Unbounded_String :=
              Ada.Strings.Unbounded.To_Unbounded_String ("Solids:");
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
              (Status_Label,
               "Geometry Status" &
               Ada.Characters.Latin_1.LF &
               "Solid count:" & Natural'Image (Count));
         end;

         declare
            Count : constant Natural := Forge.UI.History_Count;
            Lines : Ada.Strings.Unbounded.Unbounded_String :=
              Ada.Strings.Unbounded.To_Unbounded_String
                ("Command History:");
         begin
            if Count = 0 then
               Ada.Strings.Unbounded.Append (Lines, " (none)");
            else
               for I in 1 .. Count loop
                  Ada.Strings.Unbounded.Append
                    (Lines,
                     Ada.Characters.Latin_1.LF &
                     Integer'Image (I) & ". " &
                     Forge.UI.History_Line (I));
               end loop;
            end if;

            Adi.Widget.Label.Set_Text
              (History_Label, Ada.Strings.Unbounded.To_String (Lines));
         end;
      end;
   end On_Execute;

   --  Gets the solid name from the export input field.
   --  Displays the generated export command in the main command field,
   --  then executes it through the existing command handler.
   procedure On_Export (Widget : Widget_Handle) is

      Name : constant String :=
        Adi.Widget.Text_Input.Get_Text (Export_Input);
   begin
      if Name'Length = 0 then
         Adi.Widget.Label.Set_Text
           (Result_Label, "Enter a solid name to export.");
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
            On_Execute (Widget);
         end;
      end if;
   end On_Export;

   --  Handles the Enter key based on which input field has focus.
   --  Executes a Forge command from the main input field or exports
   --  a solid to STL from the export field.
   --  Prevents repeated execution when Enter is held down.
   procedure On_Enter_Key
     (Scancode : Adi.SDL.Events.SDL_Scancode;
      Keycode  : Adi.SDL.Events.SDL_Keycode;
      Key_Mod  : Adi.SDL.Events.SDL_Keymod;
      Repeat   : Boolean;
      Handled  : in out Boolean)
   is
      pragma Unreferenced (Keycode, Key_Mod);
      use type Adi.SDL.Events.SDL_Scancode;
   begin
      if not Repeat
        and then Scancode = Adi.SDL.Events.SDL_SCANCODE_RETURN
      then
         if Get_Focus_Handle (W) = Widget_Handle'(+Blink_Input) then
            On_Execute (Widget_Handle'(+Blink_Input));
            Handled := True;

         elsif Get_Focus_Handle (W) =
           Widget_Handle'(+Export_Input)
         then
            On_Export (Widget_Handle'(+Export_Input));
            Handled := True;
         end if;
      end if;
   end On_Enter_Key;

   --  Controls the blinking text cursors in both input text fields.
   --  Uses the elapsed time to alternate the cursor styles
   --  between visible and transparent every half-second.
   procedure On_Caret_Tick (DT : Duration) is
   begin
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
      Adi.Window.Extent (Px (900.0), Px (600.0)));

   declare
      --  Root container holds the command controls and both panels.
      Root : constant Adi.Widget.Box.Box_Handle :=
        Adi.Widget.Box.Create_Handle;

      --  Container that arranges the two panels horizonally.
      Panels : constant Adi.Widget.Box.Box_Handle :=
        Adi.Widget.Box.Create_Handle;

      --  Holds the command input and Execute button side by side.
      Command_Row : constant Adi.Widget.Box.Box_Handle :=
         Adi.Widget.Box.Create_Handle;

      --  Left panel displays the CSG tree, solids, and command history.
      Left_Panel : constant Adi.Widget.Box.Box_Handle :=
        Adi.Widget.Box.Create_Handle;

      --  Right panel displays geometry status and STL export controls.
      Right_Panel : constant Adi.Widget.Box.Box_Handle :=
        Adi.Widget.Box.Create_Handle;

      --  Display geometry status and command history.
      Info_Panel : constant Adi.Widget.Box.Box_Handle :=
         Adi.Widget.Box.Create_Handle;

      --  Holds the command history in a scrollable area.
      History_Box : constant Adi.Widget.Box.Box_Handle :=
         Adi.Widget.Box.Create_Handle;

      --  Contains the STL export controls.
      Export_Panel : constant Adi.Widget.Box.Box_Handle :=
         Adi.Widget.Box.Create_Handle;

      --  ** Placeholder for the CSG tree output
      CSG_Label : constant Adi.Widget.Label.Label_Handle :=
        Adi.Widget.Label.Create_Handle
          ("CSG Tree - pending integration");

      Title : constant Adi.Widget.Label.Label_Handle :=
        Adi.Widget.Label.Create_Handle ("Forge Geometry Library");

      Input : constant Adi.Widget.Text_Input.Text_Input_Handle :=
        Adi.Widget.Text_Input.Create_Handle ("");

      Execute_Button : constant Adi.Widget.Button.Button_Handle :=
        Adi.Widget.Button.Create_Handle ("Execute");

      Export_Button : constant Adi.Widget.Button.Button_Handle :=
        Adi.Widget.Button.Create_Handle ("Export STL");

   begin
      Blink_Input := Input;

      --  Create the labels and input fields used to display
      --  model information and provide STL export controls.
      Result_Label :=
        Adi.Widget.Label.Create_Handle ("Enter a command to begin.");

      Solids_Label :=
        Adi.Widget.Label.Create_Handle ("Solids: (none)");

      History_Label :=
        Adi.Widget.Label.Create_Handle ("Command History: (none)");

      Status_Label :=
        Adi.Widget.Label.Create_Handle
          ("Geometry Status" &
           Ada.Characters.Latin_1.LF &
           "Solid count: 0");

      Export_Label :=
        Adi.Widget.Label.Create_Handle ("Solid to export:");

      Export_Input :=
        Adi.Widget.Text_Input.Create_Handle ("");

      --  Apply the appearance and layout styles to the GUI widgets.
      Set_Part_Style
        (Widget_Handle'(+Root),
         Main_Part,
         Adi.Widget_Styles.Create.Base (Root_Style).Build);

      Set_Part_Style
        (Widget_Handle'(+Title),
         Label_Part,
         Adi.Widget_Styles.Create.Base (Title_Style).Build);

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
      Add_Child (Widget_Handle'(+Root), Widget_Handle'(+Title));

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

      Set_Part_Style
        (Widget_Handle'(+Left_Panel),
         Main_Part,
         Adi.Widget_Styles.Create.Base (Panel_Style).Build);

      --  Arrange the right-side sections vertically.
      Set_Part_Style
         (Widget_Handle'(+Right_Panel),
          Main_Part,
          Adi.Widget_Styles.Create.Base (Right_Stack_Style).Build);

      --  Style the geometry status and command history section.
      Set_Part_Style
         (Widget_Handle'(+Info_Panel),
          Main_Part,
          Adi.Widget_Styles.Create.Base (Panel_Style).Build);

      --  Give command history its own scrollable area.
      Set_Part_Style
         (Widget_Handle'(+History_Box),
          Main_Part,
          Adi.Widget_Styles.Create.Base (History_Scroll_Style).Build);

      --  Style the separate STL export section.
      Set_Part_Style
         (Widget_Handle'(+Export_Panel),
          Main_Part,
          Adi.Widget_Styles.Create.Base (Export_Panel_Style).Build);

      --  Display the CSG tree and solids in the left panel.
      Add_Child (Widget_Handle'(+Left_Panel),
                 Widget_Handle'(+CSG_Label));

      Add_Child (Widget_Handle'(+Left_Panel),
                 Widget_Handle'(+Solids_Label));

      --  Display geometry status and command history together.
      Add_Child (Widget_Handle'(+Info_Panel),
                 Widget_Handle'(+Status_Label));

      --  Place command history inside its scrollable container.
      Add_Child (Widget_Handle'(+History_Box),
                 Widget_Handle'(+History_Label));

      Add_Child (Widget_Handle'(+Info_Panel),
                 Widget_Handle'(+History_Box));

      --  Keep the STL export controls in their own section.
      Add_Child (Widget_Handle'(+Export_Panel),
                 Widget_Handle'(+Export_Label));

      Add_Child (Widget_Handle'(+Export_Panel),
                 Widget_Handle'(+Export_Input));

      Add_Child (Widget_Handle'(+Export_Panel),
                 Widget_Handle'(+Export_Button));

      --  Stack the information and export sections on the right.
      Add_Child (Widget_Handle'(+Right_Panel),
                 Widget_Handle'(+Info_Panel));

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
      Add_Child (Widget_Handle'(+Root),
                 Widget_Handle'(+Result_Label));

      --  Place the command input and Execute button side by side.
      Add_Child (Widget_Handle'(+Command_Row),
                 Widget_Handle'(+Input));

      Add_Child (Widget_Handle'(+Command_Row),
                 Widget_Handle'(+Execute_Button));

      --  Position the completed command bar below the panels.
      Add_Child (Widget_Handle'(+Root),
                 Widget_Handle'(+Command_Row));

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
   Connect_Key_Down (W, On_Enter_Key'Unrestricted_Access);
   Connect_Tick (W, On_Caret_Tick'Unrestricted_Access);
   A.Run;
   Adi.MCP.Finalize;

end Forge_GUI;
