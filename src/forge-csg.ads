--  Bounded approximate mesh Booleans using transient BSP trees.
--  Caller owns scratch; inputs are unchanged. Success is a validated solid or
--  canonical Empty. Failure clears the output and supplies a reason.
--  This evaluator is tested Ada outside SPARK; selected model/numeric helpers
--  are verified separately. It is not an exact-arithmetic Boolean kernel.
with Forge.Mesh; use Forge.Mesh;

package Forge.CSG with SPARK_Mode is

   type Operation is (Union, Difference, Intersection);

   Max_Reason : constant := 64;
   subtype Reason_String is String (1 .. Max_Reason);

   Max_Polygons : constant := 16_384;
   Max_Nodes : constant := 8_192;
   Max_Corners : constant := 256;
   type Workspace is limited private;
   --  Caller owns bounded scratch storage; no allocation in the evaluator.

   procedure Apply
     (Op     : Operation;
      A, B   : Tri_Mesh;
      Result : in out Tri_Mesh;
      Ok     : out Boolean;
      Reason : out Reason_String;
      Last   : out Natural;
      Work   : in out Workspace)
     with Pre  => Well_Formed (A) and then Well_Formed (B),
          Post => Well_Formed (Result)
                  and then Last <= Max_Reason
                  and then (if not Ok then Result.NT = 0)
                  and then (if Ok then Result.NT = 0 or else Is_Solid (Result));
   --  On success, a validated solid or Empty. On failure, an empty result and reason.

private
   type Corner_Array is array (1 .. Max_Corners) of Vec3;
   type Polygon is record
      Count : Natural := 0;
      V : Corner_Array := [others => Origin];
      Normal : Vec3 := Origin;
      W : Scalar := 0.0;
      Next : Natural := 0;
   end record;
   type Polygon_Array is array (1 .. Max_Polygons) of Polygon;
   type BSP_Node is record
      Normal : Vec3 := Origin;
      W : Scalar := 0.0;
      Polys, Front, Back : Natural := 0;
   end record;
   type Node_Array is array (1 .. Max_Nodes) of BSP_Node;
   type Workspace is limited record
      P : Polygon_Array;
      N : Node_Array;
      Used_P, Used_N : Natural := 0;
   end record;
end Forge.CSG;
