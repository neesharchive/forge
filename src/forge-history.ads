--  Verified cursor semantics for bounded, branching undo/redo histories.
package Forge.History with SPARK_Mode is
   Max_Count : constant := 4096;
   subtype Count is Natural range 0 .. Max_Count;
   type Cursor is record
      Applied, Stored : Count := 0;
   end record;
   function Valid (C : Cursor) return Boolean is (C.Applied <= C.Stored);
   procedure Commit_Edit (C : in out Cursor)
     with Pre => Valid (C) and then C.Applied < Max_Count,
          Post => Valid (C) and then C.Applied = C.Applied'Old + 1
                  and then C.Stored = C.Applied;
   --  Records a successful edit and drops the redo suffix.
   procedure Undo (C : in out Cursor)
     with Pre => Valid (C) and then C.Applied > 0,
          Post => Valid (C) and then C.Applied = C.Applied'Old - 1
                  and then C.Stored = C.Stored'Old;
   --  Moves the active prefix back one edit without dropping redo.
   procedure Redo (C : in out Cursor)
     with Pre => Valid (C) and then C.Applied < C.Stored,
          Post => Valid (C) and then C.Applied = C.Applied'Old + 1
                  and then C.Stored = C.Stored'Old;
   --  Moves the active prefix forward one edit.
end Forge.History;
