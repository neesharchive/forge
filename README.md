# Forge

An Ada solid modeler driven by a replayable text document. This implementation adds
editable expression trees, working BSP mesh Booleans, undo/redo and Wavefront OBJ
export to the original seed. The public mutation interface is
`Forge.Session.Execute (Session, Line, Response)`.

## Build and run

```sh
alr -n build
cd tests
alr -n build
./bin/tests
cd ../cli
alr -n build
./bin/forge_cli ../examples/bracket.forge
cd ..
python3 tests/integration.py
```

For the terminal tree/status/command demonstration, run
`cli/bin/forge_cli --inspect`. Type one modeling command at a time. The terminal
prints the current trees and evaluated geometry status after each command.

```text
box base 40 20 10
cylinder hole 4 20 32
difference cut base hole
tree cut
bounds cut
evaluate cut
info cut
setcylinder cut R 5 20 32
undo
redo
save bracket.forge
export cut bracket.obj
```

An `ok model updated; mesh not evaluated` response means the symbolic edit
succeeded. `evaluate`, `info`, mesh read-back and export evaluate geometry.
An unsuccessful evaluation never exposes a stale mesh. Empty Boolean results are
successful, but cannot be exported as a solid OBJ. Export requires `.obj`.

## Model and history

Each named object owns an independent expression tree. Primitive leaves retain
parameters; unary transform nodes preserve operation order; binary Boolean nodes
retain ordered operands. Boolean creation and `copy` copy operand expressions.
Changing a separately named source later does **not** change an existing result.
Use subtree editing to change the result's own copied parameters.
`bounds NAME` computes conservative symbolic bounds without generating a mesh;
`info NAME` reports bounds of the evaluated mesh.

`tree cut` prints root-relative paths: `.` is the root, `L`/`R` are Boolean
children and `C` descends through a transform. Examples:

```text
params cut R
setbox cut L 50 20 10
setcylinder cut R 5 20 48
setop cut . union
swap cut .
replace cut R hole
settransform positioned . translate 10 0 0
settransform rotated . rotate z 90
settransform scaled . scale 2
```

Undo/redo replay the active history prefix into candidate state before commit.
A new successful edit after undo discards redo; a failed edit does not. Load is
transactional and accepts only modeling commands, comments and compatible format
metadata. Quoted paths support spaces. Save records the active history, not the
redo suffix or cached meshes.

## Geometry and numbers

Production evaluation uses the existing `Long_Float` scalar and bounded BSP
clipping. The declared coordinate domain is +/-10,000 mm, with an absolute
1e-8 mm positional tolerance; supported parts must have well-separated features.
This is approximate polygonal geometry, not an exact analytic CAD kernel.

Validation checks finite/ranged coordinates, nondegenerate faces, oriented edge
pairing, vertex fans, triangle intersections and shell nesting/orientation.
Validation is limited to 20,000 triangles; larger outputs fail explicitly. BSP
scratch permits 16,384 polygons, 8,192 splitter nodes and 256 corners per polygon.
Model trees permit 4,096 allocated nodes and depth 128; there are 64 named objects
and 4,096 history commands. Capacity or precision failures do not become solids.

`Forge.Fixed` and `Forge.Fixed_Geometry` are a separate fixed-grid feasibility
implementation: 2^-16 mm ticks, exact quarter turns, checked translation,
ties-to-even integer rounding, decimal parsing without a binary-float intermediate,
128-bit determinant classification and checked grid edge construction. An off-grid
intersection that cannot remain on its plane is rejected. This prototype is not a
second production BSP backend. See [numeric decision](docs/NUMERICS.md).

## SPARK verification

Run `tools/verify.sh` for the complete build, tests, independent OBJ acceptance,
flow and proof gates. Set `ALR=/absolute/path/to/alr` if needed. On macOS it selects
an installed macOS 15 SDK when available to avoid GNAT 16 linker incompatibility
with newer SDK library stubs, even if the host exports a newer SDKROOT. Set
`FORGE_SDKROOT` to explicitly override that choice. For manual builds on affected Macs, first set
`SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk`.

```sh
alr -n exec -- gnatprove -P forge.gpr --mode=flow --checks-as-errors=on
alr -n exec -- gnatprove -P forge.gpr --mode=prove --level=2 \
  --checks-as-errors=on -u forge-fixed.adb forge-model.adb forge-numeric.ads forge-history.adb
```

GNATprove is included as a verification-tool dependency. On Apple Silicon the
provided proof engine also needs GMP (`brew install gmp`). Flow and contract proof
are separate gates. The BSP evaluator, geometric validator, fixed-geometry
prototype, parser/session and OBJ encoder are tested Ada outside SPARK; the
entire floating-point Boolean algorithm is **not** formally proved. See
[verification scope](docs/VERIFICATION.md) for evidence and limits.

The old `Forge.STL` serializer remains as an independent compatibility package;
the session export command and examples use OBJ.

## Further documentation

- [Architecture](ARCHITECTURE.md)
- [Requirements and implementation stages](docs/REQUIREMENTS.md)
- [Verification](docs/VERIFICATION.md)
- [Numerical decision](docs/NUMERICS.md)

License: Apache-2.0. The BSP operation sequences are adapted from Evan Wallace's
MIT-licensed csg.js; its notice is in `NOTICE`.
