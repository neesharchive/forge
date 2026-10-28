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
--    cylinder   NAME R H [SEGMENTS]           default 32
--    translate  NAME DX DY DZ
--    rotate     NAME x|y|z DEGREES
--    scale      NAME FACTOR
--    union      NAME A B                      NAME := A + B
--    difference NAME A B                      NAME := A - B
--    intersect  NAME A B
--    copy       NAME FROM
--    delete     NAME
--    list                                     query, not recorded
--    info       NAME                          query, not recorded
--    export     NAME FILE.obj                 side effect, not recorded
--    tree       NAME                          symbolic expression query
--    bounds     NAME                          conservative symbolic bound
--    params     NAME PATH                     node parameter query
--    evaluate   NAME                          validated mesh evaluation
--    setbox     NAME PATH W H D               edit primitive
--    setcylinder NAME PATH R H SEGMENTS
--    settransform NAME PATH translate DX DY DZ | rotate AXIS DEGREES | scale FACTOR
--    setop      NAME PATH union|difference|intersect
--    replace    NAME PATH SOURCE              clone replacement subtree
--    swap       NAME PATH                     exchange Boolean operands
--    undo                                     meta
--    redo                                     meta
--    save       FILE.forge                    meta
--    load       FILE.forge                    meta
--    #  anything                              comment, ignored
--
--  Modeling commands are recorded in the session history; queries,
--  exports and meta commands are not. Save writes the history; load
--  replays it. That is the document format: this grammar, in a file.

package Forge.Commands with SPARK_Mode is

   type Kind is
     (Box, Cylinder, Translate, Rotate, Scale,
      Union, Difference, Intersect, Copy,
      Set_Box, Set_Cylinder, Set_Transform, Set_Op, Replace_Tree, Swap, Delete,
      List, Info, Tree, Params, Evaluate, Inspect_Bounds, Export, Undo, Redo, Save, Load,
      Comment, Empty);

   subtype Modeling is Kind range Box .. Delete;
   --  Recorded in the history, replayed by Load.

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
         when Cylinder =>
            Cyl_Name : Name;
            R, CH    : Scalar := 0.0;
            Segments : Positive := 32;
         when Translate =>
            Tr_Name  : Name;
            By       : Vec3;
         when Rotate =>
            Rot_Name : Name;
            About    : Axis := Z;
            Degrees  : Scalar := 0.0;
         when Scale =>
            Sc_Name  : Name;
            Factor   : Scalar := 1.0;
         when Union | Difference | Intersect =>
            Result   : Name;
            A, B     : Name;
         when Copy =>
            Cp_Name  : Name;
            From     : Name;
         when Set_Box | Set_Cylinder | Set_Transform | Set_Op | Replace_Tree | Swap =>
            Edit_Name : Name;
            Path : Path_String;
            Values : Vec3 := Origin;
            Extra : Scalar := 0.0;
            Edit_Axis : Axis := Z;
            Mode : Natural range 0 .. 2 := 0;
            Source : Name;
         when Params =>
            Param_Name : Name;
            Param_Path : Path_String;
         when Delete | Info | Tree | Evaluate | Inspect_Bounds =>
            Target   : Name;
         when Export =>
            Ex_Name  : Name;
            Ex_Path  : Path_String;
         when Save | Load =>
            File     : Path_String;
         when List | Undo | Redo | Comment | Empty =>
            null;
      end case;
   end record;

   Max_Line : constant := 512;

   procedure Parse (Line : String; C : out Command; Ok : out Boolean; Error : out Path_String)
     with Pre => Line'Length <= Max_Line;
   --  Ok = False with a message in Error for anything the grammar above
   --  does not accept. Comments and blank lines parse to Comment/Empty.

   function Image (C : Command) return String
     with Post => Image'Result'Length <= Max_Line;
   --  The canonical line. Parse (Image (C)) yields C for every modeling
   --  command. Numbers are printed with enough digits to round-trip.

end Forge.Commands;
