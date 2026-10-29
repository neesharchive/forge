package body Forge.Primitives with SPARK_Mode => Off is
   procedure Box (M : in out Tri_Mesh; W, H, D : Scalar; Ok : out Boolean) is
      X : constant Scalar := W / 2.0;
      Y : constant Scalar := H / 2.0;
      Z : constant Scalar := D / 2.0;
      Ix : array (1 .. 8) of Vertex_Index;
      --  Corners: bit 0 = +X, bit 1 = +Y, bit 2 = +Z, numbered 1 .. 8.
      Corners : constant array (1 .. 8) of Vec3 :=
        [(-X, -Y, -Z), (X, -Y, -Z), (-X, Y, -Z), (X, Y, -Z),
         (-X, -Y,  Z), (X, -Y,  Z), (-X, Y,  Z), (X, Y,  Z)];
      --  Twelve triangles, each CCW seen from outside.
      Faces : constant array (1 .. 12, 1 .. 3) of Positive :=
        [[1, 3, 2], [2, 3, 4],   --  -Z
         [5, 6, 7], [6, 8, 7],   --  +Z
         [1, 2, 5], [2, 6, 5],   --  -Y
         [3, 7, 4], [4, 7, 8],   --  +Y
         [1, 5, 3], [3, 5, 7],   --  -X
         [2, 4, 6], [4, 8, 6]];  --  +X
   begin
      Clear (M);
      for I in 1 .. 8 loop
         Add_Vertex (M, Corners (I), Ix (I), Ok);
         if not Ok then
            Clear (M);
            return;
         end if;
      end loop;
      for F in 1 .. 12 loop
         Add_Triangle (M, Ix (Faces (F, 1)), Ix (Faces (F, 2)), Ix (Faces (F, 3)), Ok);
         if not Ok then
            Clear (M);
            return;
         end if;
      end loop;
      Ok := True;
   end Box;

   procedure Cylinder
     (M : in out Tri_Mesh; R, H : Scalar; Segments : Positive; Ok : out Boolean)
   is
      Half : constant Scalar := H / 2.0;
      Bot, Top : array (1 .. Max_Segments) of Vertex_Index;
      CB, CT   : Vertex_Index;  --  cap centres
      procedure Tri (A, B, C : Vertex_Index);
      procedure Tri (A, B, C : Vertex_Index) is
      begin
         if Ok then
            Add_Triangle (M, A, B, C, Ok);
         end if;
      end Tri;
   begin
      Clear (M);
      Add_Vertex (M, (0.0, 0.0, -Half), CB, Ok);
      if not Ok then
         return;
      end if;
      Add_Vertex (M, (0.0, 0.0,  Half), CT, Ok);
      if not Ok then
         return;
      end if;
      for I in 1 .. Segments loop
         declare
            S, C, X, Y : Scalar;
         begin
            Sin_Cos (Scalar'(360.0 * Scalar (I - 1)) / Scalar (Segments), S, C);
            X := R * C; Y := R * S;
            Add_Vertex (M, (X, Y, -Half), Bot (I), Ok);
            if not Ok then
               Clear (M);
               return;
            end if;
            Add_Vertex (M, (X, Y,  Half), Top (I), Ok);
            if not Ok then
               Clear (M);
               return;
            end if;
         end;
      end loop;
      for I in 1 .. Segments loop
         declare
            J : constant Positive := (if I = Segments then 1 else I + 1);
         begin
            Tri (CB, Bot (J), Bot (I));                --  bottom cap, faces -Z
            Tri (CT, Top (I), Top (J));                --  top cap, faces +Z
            Tri (Bot (I), Bot (J), Top (J));           --  wall
            Tri (Bot (I), Top (J), Top (I));
         end;
      end loop;
      if not Ok then
         Clear (M);
      end if;
   end Cylinder;

end Forge.Primitives;
