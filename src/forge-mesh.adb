package body Forge.Mesh with SPARK_Mode is

   procedure Clear (M : in out Tri_Mesh) is
   begin
      M.NV := 0;
      M.NT := 0;
   end Clear;

   procedure Add_Vertex
     (M : in out Tri_Mesh; P : Vec3; Index : out Vertex_Index; Ok : out Boolean) is
   begin
      if M.NV >= M.Cap_V then
         Index := 0;
         Ok := False;
      else
         M.NV := M.NV + 1;
         M.V (M.NV) := P;
         Index := M.NV;
         Ok := True;
      end if;
   end Add_Vertex;

   procedure Add_Triangle (M : in out Tri_Mesh; A, B, C : Vertex_Index; Ok : out Boolean) is
   begin
      if M.NT >= M.Cap_T then
         Ok := False;
      else
         M.NT := M.NT + 1;
         M.T (M.NT) := (A, B, C);
         Ok := True;
      end if;
   end Add_Triangle;

   procedure Copy (From : Tri_Mesh; To : out Tri_Mesh; Ok : out Boolean) is
   begin
      To.V := [others => Origin];
      To.T := [others => (0, 0, 0)];
      To.NV := 0;
      To.NT := 0;
      if From.NV > To.Cap_V or else From.NT > To.Cap_T then
         Ok := False;
         return;
      end if;
      for I in 1 .. From.NV loop
         pragma Loop_Invariant (To.NV = 0 and then To.NT = 0);
         To.V (I) := From.V (I);
      end loop;
      for I in 1 .. From.NT loop
         pragma Loop_Invariant (To.NV = 0 and then To.NT = 0);
         To.T (I) := From.T (I);
      end loop;
      To.NV := From.NV;
      To.NT := From.NT;
      Ok := True;
   end Copy;

   ---------------------------------------------------------------------

   --  Directed edges of triangle I, in order: (A,B), (B,C), (C,A).
   procedure Edge (M : Tri_Mesh; I : Triangle_Index; K : Positive; From, To : out Vertex_Index)
     with Pre => Well_Formed (M) and then I in 1 .. M.NT and then K in 1 .. 3;

   procedure Edge (M : Tri_Mesh; I : Triangle_Index; K : Positive; From, To : out Vertex_Index)
   is
   begin
      case K is
         when 1      => From := M.T (I).A; To := M.T (I).B;
         when 2      => From := M.T (I).B; To := M.T (I).C;
         when others => From := M.T (I).C; To := M.T (I).A;
      end case;
   end Edge;

   function Is_Watertight (M : Tri_Mesh) return Boolean is
      F, T, F2, T2 : Vertex_Index;
      Twins, Dups  : Natural;
   begin
      for I in 1 .. M.NT loop
         for K in 1 .. 3 loop
            Edge (M, I, K, F, T);
            Twins := 0;
            Dups  := 0;
            for J in 1 .. M.NT loop
               for L in 1 .. 3 loop
                  Edge (M, J, L, F2, T2);
                  if F2 = T and then T2 = F then
                     Twins := Twins + 1;
                  elsif F2 = F and then T2 = T and then (I /= J or else K /= L) then
                     Dups := Dups + 1;
                  end if;
               end loop;
            end loop;
            if Twins /= 1 or else Dups /= 0 then
               return False;
            end if;
         end loop;
      end loop;
      return True;
   end Is_Watertight;

   ---------------------------------------------------------------------

   function Normal (M : Tri_Mesh; I : Triangle_Index) return Vec3 is
      A : constant Vec3 := M.V (M.T (I).A);
      B : constant Vec3 := M.V (M.T (I).B);
      C : constant Vec3 := M.V (M.T (I).C);
   begin
      return Cross (B - A, C - A);
   end Normal;

   function Volume (M : Tri_Mesh) return Scalar is
      Sum : Scalar := 0.0;
   begin
      for I in 1 .. M.NT loop
         Sum := Sum + Dot (M.V (M.T (I).A), Cross (M.V (M.T (I).B), M.V (M.T (I).C)));
      end loop;
      return Sum / 6;
   end Volume;

   procedure Bounds (M : Tri_Mesh; Lo, Hi : out Vec3) is
   begin
      Lo := Origin;
      Hi := Origin;
      if M.NV = 0 then
         return;
      end if;
      Lo := M.V (1);
      Hi := M.V (1);
      for I in 2 .. M.NV loop
         Lo := (Scalar'Min (Lo.X, M.V (I).X),
                Scalar'Min (Lo.Y, M.V (I).Y),
                Scalar'Min (Lo.Z, M.V (I).Z));
         Hi := (Scalar'Max (Hi.X, M.V (I).X),
                Scalar'Max (Hi.Y, M.V (I).Y),
                Scalar'Max (Hi.Z, M.V (I).Z));
      end loop;
   end Bounds;

end Forge.Mesh;
