package body Forge.History with SPARK_Mode is
   procedure Commit_Edit (C : in out Cursor) is
   begin
      C.Applied := C.Applied + 1;
      C.Stored := C.Applied;
   end Commit_Edit;

   procedure Undo (C : in out Cursor) is
   begin
      C.Applied := C.Applied - 1;
   end Undo;

   procedure Redo (C : in out Cursor) is
   begin
      C.Applied := C.Applied + 1;
   end Redo;
end Forge.History;
