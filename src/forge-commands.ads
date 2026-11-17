--  The command language. One line, one operation. This is the whole
--  interface between the engine and everything above it: the CLI reads
--  lines from stdin, a .forge file is lines, the GUI emits lines when
--  you click, an agent emits lines when it reasons. Parse and Image
--  are inverses; Commands_Round_Trip in tests/ checks it.
--
--  Grammar (tokens separated by spaces, numbers as Ada reals or ints,
--  names are identifiers up to Max_Name):
--
--    box        NAME W H D
--    cube       NAME LENGTH [X Y Z SCALE]
--    sphere     NAME RADIUS [X Y Z SCALE]
--    cylinder   NAME R H [SEGMENTS]           default 32
--    move       NAME X Y Z                  absolute world position
--    resize     NAME SCALE                  absolute scale about shape position
--    translate  NAME DX DY DZ
--    rotate     NAME x|y|z DEGREES
--    scale      NAME FACTOR
--    union      NAME A B [MORE ...]          group operands; geometry pending
--    difference NAME A B [MORE ...]          subtract others from A
--    intersect  NAME A B [MORE ...]
--    copy       NAME FROM
--    delete     NAME
--    list                                     query, not recorded
--    info       NAME                          query, not recorded
--    export     NAME FILE.stl                 side effect, not recorded
--    export     FILE.stl                      all top-level meshes in one STL
--    tree                                     query, not recorded
--    history                                  query, not recorded
--    redo                                     meta
--    undo                                     meta
--    save       FILE.forge                    meta
--    load       FILE.forge                    meta
--    #  anything                              comment, ignored
--
--  Modeling commands are recorded in the session history; queries,
--  exports and meta commands are not. Save writes the history; load
--  replays it. That is the document format: this grammar, in a file.

package Forge.Commands with SPARK_Mode is

   type Kind is
     (Box, Cube, Sphere, Cylinder, Translate, Move, Rotate, Scale, Resize,
      Union, Difference, Intersect, Copy, Delete,
      List, Info, Tree_View, History_View, Export, Undo, Redo, Save, Load,
      Comment, Empty);

   subtype Primitive_Kind is Kind range Cube .. Sphere;
   subtype Translation_Kind is Kind range Translate .. Move;
   subtype Scaling_Kind is Kind range Scale .. Resize;
   subtype Boolean_Kind is Kind range Union .. Intersect;
   subtype Modeling is Kind range Box .. Delete;
   --  Recorded in the history, replayed by Load.

   Max_Operands : constant := 64;
   type Name_Array is array (Positive range <>) of Name;

   Max_Path : constant := 256;

   type Path_String is record
      Length : Natural range 0 .. Max_Path := 0;
      Text   : String (1 .. Max_Path) := [others => ' '];
   end record;

   function Image (P : Path_String) return String is (P.Text (1 .. P.Length));

   type Command (K : Kind := Empty) is record
      case K is
         when Box =>
            Box_Name : Name;
            W, H, D  : Scalar := 0.0;
         when Cube | Sphere =>
            Shape_Name : Name;
            Size : Scalar := 1.0;
            Position : Vec3 := Origin;
            Initial_Scale : Scalar := 1.0;
         when Cylinder =>
            Cyl_Name : Name;
            R, CH    : Scalar := 0.0;
            Segments : Positive := 32;
         when Translate | Move =>
            Tr_Name  : Name;
            By       : Vec3;
         when Rotate =>
            Rot_Name : Name;
            About    : Axis := Z;
            Degrees  : Scalar := 0.0;
         when Scale | Resize =>
            Sc_Name  : Name;
            Factor   : Scalar := 1.0;
         when Union | Difference | Intersect =>
            Result   : Name;
            A, B     : Name;
            Extra_Count : Natural range 0 .. Max_Operands - 2 := 0;
            Extra : Name_Array (1 .. Max_Operands - 2) := [others => <>];
         when Copy =>
            Cp_Name  : Name;
            From     : Name;
         when Delete | Info =>
            Target   : Name;
         when Export =>
            Ex_Name  : Name; -- empty selects whole-workspace export
            Ex_Path  : Path_String;
         when Save | Load =>
            File     : Path_String;
         when List | Tree_View | History_View | Undo | Redo | Comment | Empty =>
            null;
      end case;
   end record;

   Max_Line : constant := 4096;

   procedure Parse (Line : String; C : out Command; Ok : out Boolean; Error : out Path_String)
     with Pre => Line'Length <= Max_Line;
   --  Ok = False with a message in Error for anything the grammar above
   --  does not accept. Comments and blank lines parse to Comment/Empty.

   function Image (C : Command) return String
     with Post => Image'Result'Length <= Max_Line;
   --  The canonical line. Parse (Image (C)) yields C for every modeling
   --  command. Numbers are printed with enough digits to round-trip.

end Forge.Commands;
