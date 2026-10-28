# Verification evidence

Verified October 27, 2026 on macOS ARM64 using GNAT 16.1.0, GNATprove 16.1.0
and GPRbuild 26.0.1. The in-place build uses the already-installed macOS 15 SDK
because GNAT 16's linker rejected the newer Xcode SDK library stubs. The verification
script selects that compatible SDK locally without changing global settings. The installed project is verified again by the installation
step. Reproduce with `tools/verify.sh` (`ALR=/absolute/path/to/alr` if necessary).

## Results

| Gate | Result |
|---|---|
| Library, test executable and CLI builds | Pass with assertions, style checks and warnings as errors |
| Ada regression suite | 168 checks pass |
| Independent CLI/document/OBJ suite | 1,708 assertions pass |
| Whole-project SPARK flow | 100 checks pass; zero unproved checks |
| Selected SPARK contract/runtime-safety proof | 152 total flow/proof checks pass; zero unproved checks |
| Bracket qualification | 24, 64, 128 and 256 segment cylinders pass full evaluation |

The 152 total is the proof report's combined count, including flow checks; it does
not mean 152 independent geometric theorems. The full-flow run retains one warning
in the unmodified Bedrock dependency (`Buffers.Fill` has an unused incoming value).
There are no unproved checks. Logs and the detailed coverage report are in
[`verification/`](verification/). Source hashes are in `verification/sources.json`.

## Proof scope

The proof gate selects `Forge.Fixed`, `Forge.Numeric`, `Forge.Model` and
`Forge.History`. Covered properties include bounded allocation/count updates,
index safety and recursion/loop safety in model operations, domain-bounded numeric
comparison, exact quarter-turn arithmetic, checked fixed-grid translation,
integer rounding safety/output bounds, and undo/redo cursor transition contracts.
The rounding algorithm's nearest/tie behavior also has explicit positive and
negative regression cases; no general geometric exactness conclusion follows.

Whole-project flow analysis checks SPARK portions of Forge and instantiated
Bedrock dependencies. Parser/image, session/file I/O, OBJ encoding, BSP clipping,
geometric validation, fixed-geometry feasibility code and existing primitive/
transform implementations have bodies outside SPARK. They are tested, not formally
proved. The edge sorter is flow-checked; its equivalence to the mathematical
watertightness predicate is not a proved functional theorem in this release.

## Independent acceptance

The OBJ reader is Python standard-library code independent of the Ada serializer.
It checks finite coordinates, 1-based triangular indices, opposite oriented edge
pairs, analytic box volumes and the bracket's tessellated-hole volume/bounds.
Undo/redo and save/load reproduce identical OBJ bytes. Failed loads preserve the
current model and cannot execute export side effects. Empty/failed exports retain
an existing destination. Tests also cover profile mismatch, name/depth capacity,
redo preservation on failed edits, rotated subtraction and symbolic bounds.

Ada regressions cover primitive geometry, command round trips, all three Booleans,
empty results, identity, disjoint components, cavities, face contact, unsupported
edge contact, subtree edits, fixed-grid arithmetic and geometric rejection of
collapsed faces, inverted shells and overlapping closed shells.

## Performance and limits

The single-sample fresh-process bracket measurements are in `benchmarks.json`.
Observed evaluation times: approximately 0.6 s (24 segments), 1.9 s (64), 8.8 s
(128), 51.9 s (256). Full geometric validation is a bounded quadratic reference
implementation. These are local measurements, not cross-platform guarantees.
BSP scratch is about 100 MiB and allocated lazily only for Boolean evaluation;
primitive-only queries do not allocate it. Capacity failures identify the bounded
resource. Maximum validated output is 20,000 triangles.

Production remains approximate floating-point BSP. The fixed-grid implementation
is a separate tested feasibility backend, not a production fixed-point BSP engine.
Exact rational mesh Booleans and a graphical/OpenGL viewport are not included.
The implemented interactive front end is `forge_cli --inspect`.

An external graphical OBJ viewer and other OS builds were not run locally.
Linux/macOS CI jobs are configured, but their remote results are not claimed here.

Baseline Forge commit: `59051fdb4e333a32e4dfda2d1c898a66cb5d5904`.
Bedrock commit inspected/built: `342d5bdd0b61f65e31a18f9b0b39cf6c2d353647`.
