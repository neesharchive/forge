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
      To.NV := 0;
      To.NT := 0;
      To.V := [others => Origin];
      To.T := [others => <>];
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
      type Directed_Edge is record
         A, B : Vertex_Index;
      end record;
      type Edge_List is array (Natural range <>) of Directed_Edge;
      Edges : Edge_List (1 .. 3 * Natural (M.NT)) := [others => (0, 0)];
      Count : Natural := 0;
      F, T : Vertex_Index;

      function Less (A, B : Directed_Edge) return Boolean;
      procedure Sift (First, Last : Natural);

      function Less (A, B : Directed_Edge) return Boolean is
         A0 : constant Vertex_Index := Vertex_Index'Min (A.A, A.B);
         B0 : constant Vertex_Index := Vertex_Index'Min (B.A, B.B);
      begin
         return A0 < B0 or else
           (A0 = B0 and then Vertex_Index'Max (A.A, A.B) < Vertex_Index'Max (B.A, B.B));
      end Less;

      procedure Sift (First, Last : Natural) is
         Root : Natural := First;
         Child : Natural;
         Temp : Directed_Edge;
      begin
         while Root <= Last / 2 loop
            pragma Loop_Variant (Increases => Root);
            Child := Root * 2;
            if Child < Last and then Less (Edges (Child), Edges (Child + 1)) then
               Child := Child + 1;
            end if;
            exit when not Less (Edges (Root), Edges (Child));
            Temp := Edges (Root); Edges (Root) := Edges (Child); Edges (Child) := Temp;
            Root := Child;
         end loop;
      end Sift;
   begin
      for I in 1 .. M.NT loop
         for K in 1 .. 3 loop
            Edge (M, I, K, F, T);
            Count := Count + 1;
            Edges (Count) := (F, T);
         end loop;
      end loop;
      if Count = 0 then
         return True;
      end if;
      for I in reverse 1 .. Count / 2 loop
         Sift (I, Count);
      end loop;
      for I in reverse 2 .. Count loop
         declare
            Temp : constant Directed_Edge := Edges (1);
         begin
            Edges (1) := Edges (I); Edges (I) := Temp;
         end;
         Sift (1, I - 1);
      end loop;
      if Count rem 2 /= 0 then
         return False;
      end if;
      for I in 1 .. Count / 2 loop
         declare
            A : constant Directed_Edge := Edges (2 * I - 1);
            B : constant Directed_Edge := Edges (2 * I);
         begin
            if A.A /= B.B or else A.B /= B.A then
               return False;
            end if;
            if 2 * I < Count and then not Less (B, Edges (2 * I + 1)) then
               return False;
            end if;
         end;
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
      return Sum / Scalar'(6.0);
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
