# Forge architecture

## Dependencies and ownership

Front ends call `Forge.Session` for every mutation. `Forge.Commands` parses and
prints the language. `Forge.Model` owns bounded symbolic expression records;
`Forge.History` defines verified undo/redo cursor transitions. Session-owned state
contains named roots, model nodes and lazily generated mesh caches. Replacing a
session releases old meshes and model storage; finalization releases remaining
allocations.

`Forge.Primitives`, `Forge.Transform`, `Forge.CSG`, `Forge.Mesh`,
`Forge.Validation` and `Forge.OBJ` compute on supplied values. File I/O and
allocation belong to the session. `Forge.CSG.Workspace` is bounded scratch
allocated by its caller, not a global mutable kernel singleton.

## Four structures

1. Modeling-command history is the saved document.
2. Independent expression trees retain primitive parameters and operation order.
3. Evaluated indexed meshes are derived display/export data.
4. BSP trees are transient evaluator data and never replace the model tree.

There is a named-root forest, not one implicitly unioned scene. Binary operations
clone both operand expressions. Copy also clones. Editing a source name does not
retroactively change a prior result. Root-relative paths permit explicit subtree
editing without exposing reusable raw arena IDs.

## Transactions and replay

Every edit replays the active history into fresh candidate state, applies one
command and checks expression arity/depth before commit. This deliberately favors
simple atomic behavior over incremental caches. Failed edits leave names, roots,
meshes, history and redo unchanged. Undo/redo similarly commit only successful
candidate replay. Replay failures are checked.

Load constructs a candidate session and rejects side effects. The current session
is replaced only after every accepted document line has replayed. Save records
format/profile metadata and the active modeling prefix. Save/export use temporary
sibling files and rename after successful close.

## Evaluation and failure

Edits construct expressions; evaluation is requested by `evaluate`, `info`,
`Mesh_Of` or export. Primitive/transform operations are reused in a postorder walk.
Boolean nodes evaluate operands to temporary meshes and call the BSP evaluator.
Intermediate allocation is released on both expected failure and exception paths.

The CSG implementation uses clip/invert/build sequences for union, intersection
and difference. Polygon construction, recursion, corner counts and output counts
are bounded. Reconstruction first gathers canonical boundary vertices, subdivides
edges at intervening vertices, then triangulates convex fragments using an interior
fan. It does not rely on endpoint welding alone to repair T-junctions.

The release validator checks edge pairing, vertex fans, self-intersections and
component nesting/orientation. The sorted-edge predicate is O(T log T); full
geometric validation deliberately uses bounded quadratic reference checks. A
successful result is either a validated nonempty mesh or canonical Empty. A
failure never publishes partial output. Edge/point contact requiring a nonmanifold
boundary is rejected. General exact-arithmetic robustness is not claimed.

Read-only mesh views expire at the next session mutation. Evaluate a failed
expression again to retry; no prior result is returned as if current.

## Export

`export NAME FILE.obj` evaluates and validates the expression, writes a Wavefront
object, decimal vertex positions and 1-based triangular face indices, closes the
temporary file and replaces the destination. OBJ preserves indexed connectivity
and does not force binary32 coordinate conversion. Millimetres are a documented
convention, not a standardized OBJ unit field. No materials, UVs or explicit normals
are required; `s off` selects flat shading.

## Numerical and proof boundaries

Production geometry uses `Long_Float` within a declared domain. The independent
fixed-grid prototype explores exact integer predicates and rejects unsafe rounded
constructions. It is not substituted into the BSP by changing one type alias.

SPARK verification covers selected numeric, bounded-tree and history contracts;
whole-project flow analysis checks the SPARK portions. Several existing and new
bodies are explicitly outside SPARK. Passing these gates does not establish exact
Boolean geometry. See `docs/VERIFICATION.md`.
