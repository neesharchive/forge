with Forge.Commands;
with Forge.Mesh;
with Forge.Numeric;
with Forge.Transform;
package body Forge.Model_Bounds with SPARK_Mode => Off is
   use Forge.Commands;
   use Forge.Mesh;
   procedure Evaluate (T : Model.Tree; Root : Model.Node_Id; B : out Box;
                       Ok : out Boolean; Depth : Natural := 0)
   is
      C : Command;
      L, R : Box;
      Good : Boolean;
      M : Tri_Mesh (8, 0);
   begin
      B := (others => <>); Ok := False;
      if Root = 0 or else Root > T.Used or else Depth > Model.Max_Depth then
         return;
      end if;
      C := T.Nodes (Root).Payload;
      case C.K is
         when Commands.Box =>
            B := (False, (-C.W / 2.0, -C.H / 2.0, -C.D / 2.0),
                  (C.W / 2.0, C.H / 2.0, C.D / 2.0));
         when Cylinder =>
            B := (False, (-C.R, -C.R, -C.CH / 2.0), (C.R, C.R, C.CH / 2.0));
         when Translate | Rotate | Scale =>
            Evaluate (T, T.Nodes (Root).Left, B, Good, Depth + 1);
            if not Good then
               return;
            end if;
            if not B.Empty then
               Clear (M); M.NV := 8;
               for I in 0 .. 7 loop
                  M.V (Vertex_Index (I + 1)) :=
                    ((if I rem 2 = 0 then B.Lo.X else B.Hi.X),
                     (if (I / 2) rem 2 = 0 then B.Lo.Y else B.Hi.Y),
                     (if I < 4 then B.Lo.Z else B.Hi.Z));
               end loop;
               case C.K is
                  when Translate => Transform.Translate (M, C.By);
                  when Rotate => Transform.Rotate (M, C.About, C.Degrees);
                  when Scale => Transform.Scale (M, C.Factor);
                  when others => null;
               end case;
               Mesh.Bounds (M, B.Lo, B.Hi);
            end if;
         when Union | Difference | Intersect =>
            Evaluate (T, T.Nodes (Root).Left, L, Good, Depth + 1);
            if not Good then
               return;
            end if;
            Evaluate (T, T.Nodes (Root).Right, R, Good, Depth + 1);
            if not Good then
               return;
            end if;
            if C.K = Difference then
               B := L;
            elsif C.K = Union then
               if L.Empty then
                  B := R;
               elsif R.Empty then
                  B := L;
               else
                  B := (False,
                        (Scalar'Min (L.Lo.X, R.Lo.X), Scalar'Min (L.Lo.Y, R.Lo.Y),
                         Scalar'Min (L.Lo.Z, R.Lo.Z)),
                        (Scalar'Max (L.Hi.X, R.Hi.X), Scalar'Max (L.Hi.Y, R.Hi.Y),
                         Scalar'Max (L.Hi.Z, R.Hi.Z)));
               end if;
            elsif not L.Empty and then not R.Empty then
               B := (False,
                     (Scalar'Max (L.Lo.X, R.Lo.X), Scalar'Max (L.Lo.Y, R.Lo.Y),
                      Scalar'Max (L.Lo.Z, R.Lo.Z)),
                     (Scalar'Min (L.Hi.X, R.Hi.X), Scalar'Min (L.Hi.Y, R.Hi.Y),
                      Scalar'Min (L.Hi.Z, R.Hi.Z)));
               B.Empty := B.Lo.X >= B.Hi.X or else B.Lo.Y >= B.Hi.Y or else B.Lo.Z >= B.Hi.Z;
            end if;
         when others => return;
      end case;
      Ok := B.Empty or else (Numeric.Valid (B.Lo) and then Numeric.Valid (B.Hi));
   exception
      when Constraint_Error =>
         B := (others => <>); Ok := False;
   end Evaluate;
end Forge.Model_Bounds;
