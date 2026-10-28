--  Conservative symbolic bounds, available without mesh evaluation.
with Forge.Model;
package Forge.Model_Bounds with SPARK_Mode is
   type Box is record
      Empty : Boolean := True;
      Lo, Hi : Vec3 := Origin;
   end record;
   procedure Evaluate (T : Model.Tree; Root : Model.Node_Id; B : out Box;
                       Ok : out Boolean; Depth : Natural := 0);
   --  Ok means a conservative bound, not proof of a nonempty Boolean result.
end Forge.Model_Bounds;
