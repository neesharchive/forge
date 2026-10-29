# Forge requirements and implementation plan

> Historical design draft. The production backend was subsequently converted to
> fixed48 at the user's direction. `NUMERICS.md` and `VERIFICATION.md` describe
> the implemented arithmetic and current proof scope; the floating-first policy
> below and the prototype's 2^-16 grid are not the production configuration.


Implementation specification — October 27, 2026; OBJ export revision

## 1. Purpose and status

This draft defines a path from the inspected Forge seed to an editable CSG model, working mesh Boolean operations, and validated Wavefront OBJ export. It includes an explicit fixed-point versus floating-point decision and the implementation requirements for either choice.

This is a proposed specification, not a statement that these capabilities already exist. Repository comments and architecture documents were used as evidence of existing intent; they are not new instructions from the user. The original requirements review did not modify source or execute tests. Implementation and actual verification results are recorded separately in `VERIFICATION.md`.

“Complete” means the release passes the supported geometry and numerical acceptance cases below. It does not mean exact Boolean evaluation of every possible mesh, arbitrary precision CAD, or proof of all geometric properties.

## 2. Inspected baseline

Source repository: `/Users/harrisonbrown/Documents/Software/forge/`.

| Area | Observed implementation | Required work |
|---|---|---|
| Numeric foundation | `Forge.Scalar` derives from `Long_Float`; Bedrock supplies vectors | Declare and test a numerical policy; evaluate fixed-point alternative |
| Mesh | Bounded indexed triangles; structural checks; quadratic edge-pairing check; signed volume and bounds | Faster topology validation, geometric validation, empty-result handling |
| Primitives | Centered box and tessellated cylinder | Preserve; sphere is an extension, not existing functionality |
| Transforms | Direct vertex translation, axis rotation, positive uniform scaling | Retain mesh routines; add symbolic transform representation |
| CSG | Union/difference/intersection API exists; body always reports not implemented | Implement BSP evaluation and reconstruction |
| Commands | Parse/image functions; modeling/query/file commands | Add redo, tree inspection, parameter and subtree editing |
| Session | Up to 64 named meshes and 4096 recorded modeling commands | Add symbolic model roots, transactional edits, redo cursor and explicit evaluation state |
| Undo | Decrements history and replays; replay responses are ignored | Preserve replay strategy but detect failures and commit atomically |
| Load | Clears current session, then executes file lines until failure | Stage replacement; restrict document commands; retain current model on failure |
| Export | Binary STL serializer exists in seed; session OBJ export added by implementation | Validate OBJ decimal coordinates, face indices, empty cases, atomic replacement and read-back |
| GUI | Written interface contract only | Tree/status/command demo first; viewport later |
| CI | Linux build/tests/example and SPARK flow analysis configured | Boolean regressions, export read-back, numerical profile checks, actual proof targets |

Important corrections to the seed's stated guarantees:

- `Well_Formed` checks index structure, not triangle area or self-intersections.
- Reverse-edge pairing alone does not establish vertex manifoldness, absence of self-intersection, or correct shell nesting/orientation.
- `Is_Solid` currently rejects empty meshes, although empty is a valid Boolean result.
- The CSG postcondition currently promises only structural validity, not the stronger successful-result guarantee stated in comments.
- Failed operations can affect an existing destination: `Slot_For` returns existing names and `Release` can clear them after failure. Transactions must protect prior state.
- The document currently records modeling history; it does not retain a symbolic CSG tree.
- Fixed point is not inherently unsuitable for CAD, and it does not inherently make geometry exact. Its suitability depends on range, resolution, intermediate arithmetic and permitted operations.

## 3. Product scope

### 3.1 Required release

The release shall support boxes, tessellated cylinders, translation, axis rotation, positive uniform scaling, binary union/intersection/difference, nested expressions, independent copies, deletion, parameter/subtree editing, tree/status inspection, undo/redo, script save/load and Wavefront OBJ export.

All mutations shall be expressible through `Forge.Session.Execute`. Front ends shall use read-only inspection interfaces and shall not mutate kernel objects.

### 3.2 Deferred features

Sphere, extrusion, arbitrary imported meshes, OBJ, sketches, constraints, fillets, nonuniform/negative scaling, automatic healing of arbitrary invalid meshes and exact rational constructions are separate extensions. A viewport is useful but is not required to establish Boolean/export correctness.

## 4. Required architecture and semantics

### 4.1 Four distinct representations

1. **Command history:** ordered modeling edits used for persistence and replay.
2. **Model expression:** primitive, transform and Boolean nodes that describe each current named result.
3. **Evaluated mesh:** derived triangles used for display, measurements and export.
4. **Temporary BSP:** evaluator-internal planes and polygon fragments, discarded after evaluation.

The editable model tree and the BSP are different structures. Neither should be serialized in place of the command document for this release.

### 4.2 Preserve existing command behavior

Use a table of named expression roots rather than forcing all objects under one implicit union. The existing language already supports multiple named objects and explicit result names.

For the initial implementation, each named object owns an independent binary expression tree. Boolean creation deep-copies both operand expressions; copy deep-copies its source. This costs nodes but avoids shared-subtree aliasing and complicated dependency propagation. A shared immutable DAG is a future optimization, not a release prerequisite.

Example:

```
box base 40 20 10
cylinder hole 4 20 32
difference cut base hole
```

`cut` owns `Difference(Box(...), Cylinder(...))`. Subsequent changes to the separately named `hole` shall not silently alter `cut`. To change the hole inside `cut`, use an explicit subtree edit. This snapshot rule preserves the existing mesh-oriented command behavior. A future live-linked dependency feature would require a separate design and file-format version.

Transforms shall be explicit unary nodes or an exactly ordered equivalent. Do not replace a sequence of rotations/translations with a single translation/rotation field unless equivalence is established. Transform order is observable.

### 4.3 Evaluation timing

A successful modeling command shall leave a valid model expression. A new Boolean expression may initially have mesh state `Not_Evaluated`; the session shall distinguish this from a successful geometric result. `evaluate NAME` shall perform complete evaluation and validation. `info`, renderer mesh access and export shall evaluate when needed and report failure explicitly.

Edits are undoable even when the resulting geometry cannot be meshed. No failed or stale mesh shall be exposed as the current result. `ok` for constructing an expression means the edit succeeded; only `evaluate ...` returning `ok solid` or `ok empty` means geometric evaluation succeeded. Existing scripts that only create primitives shall continue to work. This intentional change to Boolean-command success semantics must be documented.

An eager compatibility mode may evaluate before committing, but it shall not be mixed invisibly with the default semantics.

## 5. Numerical implementation requirements

### 5.1 Decision recommendation

Use the existing floating-point implementation for the first working BSP release. Isolate numerical operations behind a policy layer and require a bounded fixed-point feasibility prototype before selecting a fixed-point production profile. Delivering both complete backends simultaneously is not a prerequisite unless the team explicitly adopts that expanded scope.

The numerical decision is a required deliverable. The fixed-point prototype and its comparison report are required. Migration to fixed-point production is conditional on passing the stated gates; it must not delay completion indefinitely.

| Concern | Floating-point profile | Fixed-point profile |
|---|---|---|
| Coordinates | Existing `Long_Float`, with target characteristics checked | Integer grid coordinates with declared unit and bounds, optionally exposed through Ada fixed-point types |
| Range/resolution | Relative precision varies with magnitude | Uniform spacing, finite declared range |
| Plane predicates | Tolerances and optionally filtered exact predicates | Exact integer determinant signs only when all inputs and intermediates remain exact and in range |
| Split points | Generally rounded | Usually rational; generally not on grid and must be rounded or retained rationally |
| Rotation | Approximate trigonometric transforms | Exact quarter turns; general angles require a declared approximation policy |
| Cylinder | Tessellated approximation | Tessellated and quantized approximation |
| Proof | Index/capacity/topology contracts plus arithmetic bounds where practical | Same, plus integer overflow and rounding contracts; geometric correctness still needs its own specification |
| OBJ | Print enough decimal digits to preserve Scalar | Convert ticks to decimal units with documented rounding |

### 5.2 Common numerical requirements

**NUM-01 — Units and domain.** The release shall use millimetres. The documented supported coordinate domain shall include the bracket and acceptance fixtures. Initial qualification target: absolute coordinates up to 10,000 mm and intended feature sizes of at least 0.01 mm. These are proposed qualification limits, not measured capabilities; they become supported claims only after tests pass. Intermediate expressions and transforms must also stay in range.

**NUM-02 — Policy isolation.** Create `Forge.Numeric` or an equivalent internal interface for coordinate validation, classification, split interpolation, rounding, near-equality and export conversion. `Forge` may continue to expose public scalar/vector types during migration; a dependency cycle shall not be introduced. If different scalar instantiations are needed, move shared numeric types to a lower-level package or generic foundation.

**NUM-03 — No silent profile mixing.** A document shall declare numerical profile and format version. A loader shall reject unknown/incompatible profiles or require an explicit conversion operation with a report. A floating document shall not silently become a grid document on load.

**NUM-04 — Error classification.** Numerical failure shall be separate from invalid input, unsupported topology, capacity exhaustion and empty success.

**NUM-05 — Predicate/construction distinction.** Tests and documentation shall separately cover classification decisions and creation of new coordinates. Correct classification alone shall not be advertised as exact output geometry.

**NUM-06 — Determinism.** Replay shall be deterministic for a declared build/platform/profile. Cross-platform bit-identical transcendental calculations are not assumed. Cross-platform geometric equivalence shall use documented tolerances and invariants.

### 5.3 Floating-point production profile

**FLT-01.** Record `Scalar'Digits`, size, range and relevant machine characteristics for each supported build. Do not assume that `Long_Float` has identical representation on all platforms.

**FLT-02.** Reject non-finite values and out-of-domain values at parsing, transformation, splitting and export boundaries. Avoid relying on an unhandled arithmetic exception for user input validation.

**FLT-03.** Use one explicit tolerance configuration per evaluation, derived from model scale with declared absolute and relative components. Plane distance, positional welding and triangle area tests require dimensionally appropriate thresholds; one unexplained epsilon shall not govern everything.

**FLT-04.** The initial prototype shall benchmark a positional tolerance around `max(1e-8 mm, 1e-12 * model_extent)` against the qualification corpus. This is a starting experiment, not a guaranteed error bound. Plane normalization or equivalent norm scaling shall make classification independent of arbitrary plane coefficient magnitude.

**FLT-05.** Shared intersections shall reuse canonical construction/provenance where practical. Recomputing the same edge-plane intersection independently shall not create unstitched boundaries.

**FLT-06.** Welding shall be deterministic and bounded. If vertex welding collapses a feature or creates invalid incidence, reject the result; do not return a repaired-looking invalid solid.

**FLT-07.** General rotations shall use a documented angle unit, right-hand convention and origin. Exact quarter-turn special cases should avoid avoidable trigonometric drift.

### 5.4 Fixed-point feasibility and production alternative

**FIX-01 — Candidate representation.** Prototype grid step `q = 2^-16 mm`, with coordinate magnitude bounded by 10,000 mm. Grid step is approximately 0.00001526 mm. Store ticks explicitly or specify Ada fixed-point `Small`, range and representation constraints. This candidate is an engineering proposal to test, not a final selection.

**FIX-02 — Parse exactly before quantization.** Convert decimal input through a specified decimal/rational parser and round once to ticks. Do not parse through floating point and call the resulting value exact. Use round-to-nearest with ties-to-even, including negative cases, and report quantization when it exceeds an agreed input threshold.

**FIX-03 — Widened intermediates.** Derive bounds for differences, dot products, cross products, determinants and interpolation numerators before choosing intermediate types. At the candidate range, coordinate differences can approach 31 bits; a 3D orientation determinant needs roughly 96 magnitude bits under a conservative product/sum bound. Signed 64-bit arithmetic is insufficient for this predicate. A 128-bit intermediate may cover this particular bound if supported, but this does not establish bounds for all subsequent constructions. Verify availability with the actual compiler/prover.

**FIX-04 — Split policy.** For a crossing edge, the parameter `t = dA / (dA - dB)` is generally rational. Choose and document one of: bounded rational coordinates through evaluation, or quantized constructions with validation and rejection of unsafe cases. The release prototype shall use quantized constructions with rejection. Exact rational growth is deferred.

**FIX-05 — Consistency after rounding.** Reclassify constructed vertices against relevant incident planes and check edge connectivity after quantization. Cache shared intersections using stable provenance. If rounding makes the required constraints inconsistent, return `Precision_Insufficient`. Passing these checks is not a proof of exact continuous geometry.

**FIX-06 — Rounding bounds.** A single nearest-grid coordinate conversion has error at most `q/2` per axis and `sqrt(3)*q/2` in Euclidean distance. Repeated splits/transforms do not inherit that single-step bound; measure or derive their accumulated error separately.

**FIX-07 — Transforms.** Guarantee exact grid translation by integer ticks and exact quarter-turn rotation using swaps/sign changes. Positive scaling is exact only when the result remains representable. Other scale factors and arbitrary rotations require declared quantization and overflow handling; they shall not be silently treated as exact.

**FIX-08 — Curves.** Cylinder generation shall specify how trigonometric samples are generated and quantized. It may use a controlled floating-point boundary during tessellation, but that boundary shall be disclosed. A no-floating-point profile must instead provide qualified lookup/integer construction machinery. Fixed-point coordinates do not make a polygonal cylinder analytically circular.

**FIX-09 — Proof.** Prove bounded integer helper routines against their rounding and overflow contracts. Ada fixed-point multiplication/division shall have explicitly chosen result types and compiler/prover-qualified semantics. A type declaration alone is not an overflow or correctness proof.

**FIX-10 — Gate.** Select fixed point for production only if it passes the mandatory Boolean fixtures, range checks, shared-edge reconstruction, quantization rejection cases, OBJ serialization tests and practical timing/memory targets. Otherwise retain floating point and document the prototype findings. A decision to require fixed-point production despite this gate shall include revised scope and supported operations.

### 5.5 Required comparison report

For both profiles, record input perturbation, output volume/bounds, validation results, failure reason, output triangle count, elapsed time and peak/scratch memory. Include repeated Boolean chains, near-coplanar geometry, quarter-turn versus arbitrary rotation and out-of-range data. Explain whether differences come from tessellation, input quantization, splitting, classification or export conversion. Do not require identical triangulations across profiles.

## 6. Functional requirements

### 6.1 Document and tree

**DOC-01.** `Forge.Session` shall own history, named expression roots, evaluation statuses and derived meshes. Front ends shall not edit them directly.

**DOC-02.** History shall track `Applied_Count` and `Stored_Count`. Undo decreases the applied prefix; redo increases it. A new successful edit after undo discards the redo suffix. Failed edits and queries do not discard redo.

**DOC-03.** Replay shall build candidate state and check every command response. A failure shall identify the failing command and preserve the previously committed state.

**DOC-04.** Model mutations shall be atomic across names, nodes, parameters, history and mesh statuses. Validate capacity and arguments before commit. Replacing a name shall not destroy its previous value on failure.

**DOC-05.** Save shall persist the active modeling prefix, format version and numeric profile. Undo history after the active prefix need not survive reopening in this release. Session undo/redo shall continue to work after a save.

**DOC-06.** Load shall accept only version/profile metadata, modeling commands, comments and blanks. Reject nested load, export, save and other side effects. Build in temporary state, identify errors by line number, and replace the current document only after successful replay.

**TREE-01.** Add bounded node storage with kinds `Primitive`, `Transform` and `Boolean`. Boolean nodes shall have exactly two ordered children; transform nodes exactly one child. Named roots form a forest.

**TREE-02.** Each live node shall belong to exactly one named tree, except during private candidate construction. Nodes shall have valid child IDs, no cycles and depth within the configured limit. Unreachable temporary nodes shall not appear in inspection.

**TREE-03.** Primitive nodes shall retain dimensions and tessellation settings. Transform nodes shall retain operation type and ordered parameters. Boolean nodes shall retain operation and operand order. Meshes shall not replace this information.

**TREE-04.** Proposed initial limits are 64 named roots, 4096 nodes and depth 128, with existing mesh capacities retained provisionally. Capacity failures shall report the exhausted resource. Cloning must account for both source subtrees before commit.

**TREE-05.** Expose read-only tree inspection and parameter inspection through the session. Display node kind, children/order, parameters and evaluation state. IDs shall be accompanied by a document revision or treated as valid only until the next mutation; stale handles shall be rejected.

**TREE-06.** For scripted edits use stable root-relative paths: `.` is the root, `L`/`R` select Boolean children and `C` selects a transform child. Every command shall resolve its path against the current model and reject invalid paths before mutation.

**TREE-07.** Provide explicit dimension edits, transform-parameter edits, Boolean-operator changes, and subtree replacement. Replacement copies an independent source tree. Difference operand order shall be inspectable and editable explicitly. General drag/reparent and n-ary operators are deferred; they are not needed for complete binary CSG.

### 6.2 Proposed language additions

These commands are proposals requiring parser/image implementation and documentation; they are not available in the seed.

| Command | Meaning |
|---|---|
| `redo` | Reapply the next stored edit |
| `tree NAME` | Inspect symbolic expression |
| `evaluate NAME` | Generate and validate current mesh |
| `params NAME PATH` | Inspect node parameters |
| `setbox NAME PATH W H D` | Edit a box leaf |
| `setcylinder NAME PATH R H SEGMENTS` | Edit a cylinder leaf |
| `settransform NAME PATH translate DX DY DZ` | Change a translation node's payload |
| `settransform NAME PATH rotate AXIS DEGREES` | Change a rotation node's payload |
| `settransform NAME PATH scale FACTOR` | Change a scale node's payload |
| `setop NAME PATH union|difference|intersect` | Edit a Boolean node |
| `replace NAME PATH SOURCE` | Replace a subtree with an independent copy of SOURCE |
| `swap NAME PATH` | Exchange a Boolean node's operands |

Existing `translate`, `rotate` and `scale` append a transform outside the target's current expression. `copy` clones the expression. Existing destination overwrite behavior shall remain supported transactionally, except a Boolean destination equal to either operand remains rejected in this release.

Every modeling command shall have parse/image round-trip tests, replay tests and one documented example. Paths containing spaces shall use a documented quoting syntax or be rejected clearly; the seed's simple tokenization shall not silently truncate them.

### 6.3 Boolean evaluation

**BOOL-01.** Implement union, intersection and ordered difference over evaluated operand meshes using bounded BSP polygon clipping. Preserve the public `Forge.CSG` role; add explicit scratch/context/status parameters where required.

**BOOL-02.** Implement regularized solid operations: retain volumetric interiors and their boundaries; isolated points/edges/faces are not standalone solid output.

**BOOL-03.** Distinguish successful `Solid`, successful `Empty`, and failure. Canonical empty mesh has `NV = 0`, `NT = 0`; volume is zero and bounds are absent. Empty is not an invalid solid and is not a numerical failure.

**BOOL-04.** Support identity cases and empty operands: `A union A = A`, `A intersect A = A`, `A - A = Empty`; union with Empty returns A, intersection with Empty returns Empty, A minus Empty returns A, and Empty minus A returns Empty.

**BOOL-05.** Support disjoint components and cavities. Cavity boundary orientation shall oppose its containing outer shell. Positive total signed volume alone shall not be the shell-orientation test.

**BOOL-06.** For accepted geometry, remove internal interfaces and duplicate coplanar surface patches. Difference shall orient newly exposed cavity faces correctly.

**BOOL-07.** Face-sharing boxes whose union forms a valid manifold shall be supported. Edge-only/point-only touching unions that require non-manifold boundary shall return `Unsupported_Topology`; their regularized intersection is Empty. Shared-face-only intersection is also Empty.

**BOOL-08.** Implement polygon splitting, coplanar orientation handling, inversion and the full operation sequences. Difference shall not be approximated by dropping whole input triangles whose centers lie inside B.

**BOOL-09.** Reconstruct indexed meshes with consistent shared vertices and edge subdivisions. Welding equal endpoints alone does not eliminate T-junctions; a long edge adjacent to split edges shall be subdivided conformingly.

**BOOL-10.** Triangulation shall preserve polygon boundaries/winding. If the chosen splitting representation guarantees convex polygons, document and test that invariant before using fan triangulation.

**BOOL-11.** Bound BSP nodes, polygon count, polygon vertices, work-stack depth, intersections and output mesh size. Abort before writing beyond capacity. No unbounded recursion shall depend on arbitrary input size.

**BOOL-12.** Successful nonempty output shall pass the release validator. Failure shall expose no partial result and shall leave inputs unchanged. Session state and history remain unchanged for failed evaluation requests, except diagnostic/evaluation-status metadata.

**BOOL-13.** Candidate status categories: `Invalid_Input`, `Out_Of_Range`, `Capacity_Exceeded`, `Precision_Insufficient`, `Unsupported_Topology`, `Invalid_Output`, and `Internal_Error`. Messages shall identify the operation and relevant resource/check.

### 6.4 Evaluation and inspection

**EVAL-01.** Traverse the tree postorder. Generate primitive meshes at leaves, apply transforms, and call CSG at Boolean nodes. Reuse current primitive and transform routines after their numeric checks are strengthened.

**EVAL-02.** The first version may regenerate the whole named tree after an edit. It shall manage bounded live intermediate meshes rather than storing a maximum-sized mesh at every node. If workspace is insufficient, return a capacity error.

**EVAL-03.** Separate symbolic conservative bounds from bounds of an evaluated mesh. Union merges bounds; intersection overlaps operand bounds; difference can conservatively retain A's bounds. An overlapping bound does not prove nonempty intersection.

**EVAL-04.** `info` shall report profile, evaluation status, validation level, component count, counts, volume and bounds when available. It shall distinguish unevaluated, empty and failed results; no stale “solid yes”.

**EVAL-05.** Read-only mesh views shall have a documented lifetime, at most until the next session operation that can mutate/evaluate state. Front ends shall reacquire them and shall not retain dangling views across replay.

**EVAL-06.** Optional point-membership inspection shall classify Inside, Outside, Boundary or Indeterminate with declared tolerance. It supports debugging but is not a replacement for mesh Boolean construction.

## 7. Mesh validity requirements

**VAL-01 — Structure.** All counts and indices shall be in range; triangle vertex indices shall be distinct.

**VAL-02 — Geometry.** Coordinates shall be finite/in-range, triangles shall exceed a declared area threshold, and duplicate faces shall be detected.

**VAL-03 — Edges.** Each undirected edge shall occur exactly twice with opposite directions. Use sorted edges or a bounded hash structure; retain a reference implementation for small-fixture comparison. Target sort-based complexity is O(T log T).

**VAL-04 — Vertices.** Each vertex's incident faces shall form the required single closed manifold fan for its surface component. Edge pairing alone shall not authorize a “manifold” claim.

**VAL-05 — Embedding.** Detect nonincident triangle intersections and geometric overlaps, distinguishing legitimate adjacency. An initially slower reference checker is acceptable for small release fixtures. If large-output self-intersection checking is not implemented, that validation level shall be disclosed and such output shall not receive an unrestricted fully validated claim. Full release export requires this check within the supported output limits.

**VAL-06 — Shells.** Determine connected components and containment/nesting, orient outer shells outward and cavity shells inward, and reject ambiguous or intersecting shells. Disconnected valid solids are allowed.

**VAL-07 — Reporting.** Validation shall report the failed property and offending indices where possible. Keep structural validity, edge closure, manifoldness and geometric validity as separate predicates/statuses.

**VAL-08 — No cosmetic healing.** Dropping small triangles or welding nearby vertices is permitted only as a documented reconstruction step followed by full revalidation. Never claim success solely because cracks became visually small.

## 8. Export requirements (OBJ supersedes the original STL proposal)

**EXP-01.** `export NAME FILE.obj` shall write Wavefront OBJ. Reject non-OBJ destination extensions explicitly. The legacy `Forge.STL` package may remain available independently.

**EXP-02.** Evaluate and geometrically validate the current expression first. Empty or failed geometry shall produce a clear error and preserve an existing destination.

**EXP-03.** Emit an object name, finite `v x y z` positions and 1-based triangular `f a b c` records. Preserve winding and shared indices. Emit `s off`; materials, UVs and explicit normals are not required. Consumers may derive facet normals.

**EXP-04.** Use locale-independent decimal output with enough significant digits to round-trip `Scalar`; OBJ does not require converting coordinates to binary32. Preserve millimetres by convention and state units in a comment because OBJ does not standardize unit metadata.

**EXP-05.** Write a temporary sibling file, close it, then replace the destination using the platform rename operation. Report replacement failure and clean up the temporary file. An existing temporary path shall not be overwritten.

**EXP-06.** Export shall not add history entries, mutate expressions or change the undo/redo cursor. Independent OBJ read-back shall check indices, coordinates, reverse-edge closure, volume and bounds.

## 9. Reliability, performance and proof

**NFR-01.** Kernel computation shall remain independent of files, windows and session-owned allocation. Caller-supplied bounded scratch storage may be added to CSG/validation APIs.

**NFR-02.** Expected invalid input, precision limits and capacity failures shall return structured status. Internal programming errors shall remain distinguishable in diagnostics; broad exception handlers shall not hide them as ordinary geometry failures.

**NFR-03.** Preserve memory ownership across session replay, repeated load and destruction. Provide cleanup/finalization for session-owned allocations. Avoid per-node allocation of full-capacity meshes.

**NFR-04.** Proposed qualification targets: tree-only edit/inspection under 100 ms for 100 nodes, bracket evaluation under 5 seconds and export under 1 second after evaluation, on a documented reference machine/build. These are targets to measure before adopting as release guarantees. Record timing for 24/64/128/256-segment cylinders and repeated Boolean chains.

**NFR-05.** Run existing tests plus new regressions in CI. Add Windows/macOS build/test jobs before claiming those platforms supported. Record compiler, dependencies and numerical profile.

**PRF-01.** SPARK flow analysis is a separate gate from proof. State exactly which checks are proved, tested, assumed or outside SPARK.

**PRF-02.** First proof targets: count/index bounds, append/copy behavior, sorted-edge validator equivalence on its specification, tree child/range invariants, history cursor bounds and arithmetic helper contracts. Extend only after these are stable.

**PRF-03.** Prove fixed-point intermediate overflow/rounding properties if that profile is selected. For floating point, establish input domain and arithmetic checks where supported; retain numerical regression testing.

**PRF-04.** Do not claim that positive signed volume implies every shell is outward oriented, or that unchanged triangle indices imply preserved geometric validity after overflow, rounding or collapsing transformations.

**PRF-05.** Numerical Boolean correctness shall require separately specified geometric properties. “SPARK enabled” and “no runtime errors proved” shall not be presented as proof of exact Boolean geometry.

## 10. Implementation sequence and exit gates

### Stage 0 — Establish reproducible baseline

Build library, CLI and tests in an approved development environment; capture actual results. Preserve passing fixtures and the existing bracket script. Record numeric characteristics, memory layout and current command behavior. Add regression cases exposing destination overwrite failure and nontransactional load before fixing those issues.

Exit: baseline report and regression corpus exist. Do not report tests read during this draft as tests executed.

### Stage 1 — Decide numbers and define outcomes

Introduce numeric policy helpers and structured geometry statuses. Define canonical Empty and change session validation so empty Boolean results are legal. Run the fixed-point prototype: exact quarter turns, bounded determinant classification, edge split quantization and overflow rejection. Produce the profile comparison/decision report.

Exit: production numeric profile selected with rationale; uncertain numerical cases have explicit failure behavior; no type-only fixed-point migration.

### Stage 2 — Make documents transactional and redoable

Introduce active/stored history cursors, staged replay, transactional destination replacement, strict staged loading and version/profile metadata. Add redo to grammar and command image. Detect replay failure instead of ignoring responses.

Exit: undo-all/redo-all restores semantic state; invalid commands and failed loads preserve current document and redo tail; save/load restores the active model.

### Stage 3 — Add symbolic trees and live inspection

Implement node arena, independent named roots, cloning and ordered transform/Boolean nodes. Extend existing modeling dispatch to construct expressions. Add tree/parameter queries and targeted subtree edits. Use primitive evaluation plus conservative bounds before CSG exists.

Exit: command prompt can create/move/rotate objects, build nested Boolean expressions, edit a nested primitive, undo/redo and reload the same expressions. `evaluate` reports Boolean unavailability honestly until Stage 6. The tree/status panels are useful without a viewport.

### Stage 4 — Strengthen mesh validation

Implement sorted-edge validation, vertex-fan checks, component/orientation analysis and small-fixture self-intersection checks. Add explicit empty handling and validation-level reporting. Build adversarial fixtures: open surface, flipped face, duplicate face, degenerate triangle, bow-tie vertex and self-intersecting closed mesh.

Exit: validator rejects each faulty fixture for the right reason and accepts valid disconnected/cavity fixtures. Existing primitives still pass.

### Stage 5 — Build BSP mechanics independently

Implement planes, polygon representation, classification, edge splitting, inversion, bounded build/traversal and coplanar routing. Test polygon area/winding conservation and shared intersection reuse. Add scratch exhaustion/depth tests before whole Boolean composition.

Exit: each operation has focused fixtures, bounded failure paths and documented tolerances/rounding. A split square's reconstructed area matches its input within the profile bound.

### Stage 6 — Finish all three Booleans and reconstruct meshes

Implement complete reference operation sequences; triangulate, canonicalize vertices, resolve T-junctions and validate. First pass identity/disjoint/containment cases, then overlapping boxes, then box-cylinder cuts, then rotated and chained expressions. Add full validation of supported output sizes.

Exit: mandatory matrix below passes. Capacity, precision and unsupported-contact cases fail safely. Output correctness is checked by volume, bounds, sampled membership and geometry validation, not a single `Is_Solid` flag.

### Stage 7 — Complete OBJ export and end-to-end demo

Qualify precision-preserving OBJ serialization, triangular face winding, temporary-file replacement and independent parsing. Extend the bracket script with explicit evaluation and export. Add numeric-profile metadata and documentation examples.

Exit: fresh process loads script, evaluates cut, validates it, exports OBJ, independent reader checks it and external viewer opens it. Undo/edit/redo produces the expected changed and restored outputs.

### Stage 8 — Front end and release evidence

Build tree/status/REPL panels around session read-back. Add viewport if time permits. Run proof targets, platform qualification and performance measurements. Document known unsupported cases and the distinction between model tree and BSP.

Exit: reproducible release checklist, test results and proof scope accompany the implementation.

## 11. Mandatory acceptance matrix

Use centered boxes A with dimensions 2×2×2, and B identical translated +1 along X unless otherwise stated. Volumes are cubic millimetres. Compare geometry, not triangle ordering.

| ID | Scenario | Expected result |
|---|---|---|
| AT-01 | A union B | Volume 12; bounds X [-1,2], Y/Z [-1,1]; valid single solid |
| AT-02 | A intersect B | Volume 4; bounds X [0,1], Y/Z [-1,1] |
| AT-03 | A minus B | Volume 4; bounds X [-1,0], Y/Z [-1,1] |
| AT-04 | Identical operands | Union/intersection equal A geometrically; difference Empty |
| AT-05 | B translated +3 X | Union volume 16 with two components; intersection Empty; A-B equals A |
| AT-06 | Centered outer box 4³ and inner box 2³ | Difference volume 56, inner cavity oriented correctly; intersection volume 8 |
| AT-07 | B translated +2 X, face contact | Union volume 16 with internal face removed; intersection Empty; difference equals A |
| AT-08 | Boxes touch only at edge or point | Union rejected as unsupported non-manifold output; intersection Empty |
| AT-09 | Box/cylinder through-cut | Closed manifold hole; removed volume matches actual tessellated operand intersection, not ideal pi approximation alone |
| AT-10 | Rotated operand and repeated Boolean chain | Valid result or only explicitly qualified precision-limit cases; mandatory well-separated fixtures succeed |
| AT-11 | Long-edge/short-edge reconstruction | No T-junction; conformity and manifold checks pass |
| AT-12 | All invalid-mesh fixtures | Specific validation failures, never successful export |
| AT-13 | Scratch/node/mesh/history limit | Explicit error; committed state and history unchanged |
| AT-14 | Undo-all, redo-all, branch after undo | Same semantic model restored; new edit removes redo suffix only on success |
| AT-15 | Failed load / nested export in document | Current document and files unchanged; offending line reported |
| AT-16 | Save/reload | Same expressions, profile, parameters, evaluation outcomes and bounds within profile policy |
| AT-17 | OBJ read-back | Valid 1-based triangle indices, finite coordinates, closed oriented edges, expected volume and bounds |
| AT-18 | Fixed-point prototype edge crossing off grid | Declared rounding and consistency checks; unsafe case returns Precision_Insufficient |
| AT-19 | Numeric range and near-limit arithmetic | Out-of-range input and unsafe intermediate rejected without wraparound |
| AT-20 | Near-coplanar perturbations | Declared tolerance behavior; no invalid successful output; tests on both sides of thresholds |
| AT-21 | Numeric profile mismatch | Clear rejection or explicit conversion; no silent reinterpretation |
| AT-22 | Stale node/mesh handle | Rejected or invalidated according to published lifetime, never edits the wrong node |

Set fixture-specific tolerances from the declared numeric policy before judging results. Use analytically derived volumes for boxes. For polygonal cylinders use tessellated geometry as the Boolean reference. Keep a few independent high-precision/reference-tool comparisons outside the production kernel.

## 12. End-to-end demonstration

The existing bracket has a base 60×8×40 and a wall 8×50×40 translated to (-26,29,0). Those faces meet at Y=4, so successful face-contact union is a meaningful required case. The cylinder is rotated to pass through the base along Y.

```
box base 60 8 40
box wall 8 50 40
translate wall -26 29 0
union bracket base wall
cylinder hole 4 10 24
rotate hole x 90
translate hole 15 0 0
difference cut bracket hole
tree cut
evaluate cut
info cut
save bracket.forge
export cut bracket.obj
undo
redo
evaluate cut
```

`save` and `export` are not modeling edits, so the shown undo removes the last modeling command, `difference`, and redo restores it. The 24-sided hole is a tessellated circular approximation. In this configuration it lies away from the wall and passes through the base; the expected removed volume is the 24-gon's area times the base thickness of 8 mm. The bracket volume before cutting is 60×8×40 + 8×50×40 = 35,200 mm³ because the base and wall share a face without overlapping volume.

Tree panel: show `Difference(Union(base expression, translated wall expression), transformed cylinder expression)`. Status panel: show evaluation state, profile, validation, volume/bounds and counts. Prompt panel: show commands and precise responses. The independent named sources remain unchanged when the copied subtree inside `cut` is edited.

## 13. Package-level change map

| Package/file | Planned responsibility |
|---|---|
| `Forge` / new numeric foundation | Public units/types plus lower-level numeric representation boundary |
| New `Forge.Numeric` | Classification, checked construction, quantization and conversion policy |
| New `Forge.Model` | Bounded expression forest, clones, paths, edits and invariants |
| New `Forge.Evaluate` | Postorder evaluation, bounded workspace and per-root status |
| `Forge.Mesh` / new validation child package | Structural/edge/manifold/geometric validation and measures |
| `Forge.CSG` and internal BSP packages | Complete mesh Boolean evaluation; bounded scratch; reconstruction |
| `Forge.Primitives`, `Forge.Transform` | Reused mesh routines with numeric-domain checks |
| `Forge.Commands` | Redo, model inspection/edit grammar, parse/image round trips |
| `Forge.Session` | Transactions, history cursors, staged replay/load, names, model and mesh ownership |
| `Forge.OBJ` | Precision-preserving OBJ vertex and triangular-face encoding |
| `Forge.Session` file helpers | Safe file lifecycle and replacement |
| `tests/` | Baseline, numerical, tree/history, Boolean, validation and independent export checks |
| `cli/`, future `ui/` | Session-only edits and read-only inspection/rendering |

Introduce internal packages incrementally; package names are a proposal, whereas responsibilities and acceptance behavior are required.

## 14. Technical basis and limits

- [Inspected README](/Users/harrisonbrown/Documents/Software/forge/README.md), [architecture](/Users/harrisonbrown/Documents/Software/forge/ARCHITECTURE.md), [session implementation](/Users/harrisonbrown/Documents/Software/forge/src/forge-session.adb), [mesh specification](/Users/harrisonbrown/Documents/Software/forge/src/forge-mesh.ads), [CSG placeholder](/Users/harrisonbrown/Documents/Software/forge/src/forge-csg.adb), and [STL implementation](/Users/harrisonbrown/Documents/Software/forge/src/forge-stl.adb) establish the local baseline.
- [csg.js annotated implementation](https://evanw.github.io/csg.js/docs/) supplies an understandable BSP reference and the complete clip/invert sequences. Its compact implementation does not itself establish Forge's numerical, topology or bounded-storage guarantees.
- [CGAL Boolean operations manual](https://doc.cgal.org/6.2/PMP_Boolean_operations/index.html) distinguishes manifold output restrictions, exact predicates and exact constructions, and explains why rounded constructions may introduce self-intersections. This informs the validation and unsupported-contact requirements; it does not require adopting CGAL as a dependency.
- [AdaCore SPARK usage guidance](https://docs.adacore.com/spark2014-docs/html/ug/en/usage_scenarios.html) distinguishes proof objectives and explains portability considerations for floating/fixed-point arithmetic. Fixed-point multiplication/division and elementary functions require explicit qualification of the actual toolchain.

The chosen first-release method is bounded mesh BSP with validated output, not a guarantee of arbitrary-mesh exactness. If the BSP prototype cannot pass the required corpus with manageable reconstruction complexity, pause expansion and write a replacement-backend decision using the same tree and evaluator contracts. Do not weaken “valid result” to make a demonstration pass.
