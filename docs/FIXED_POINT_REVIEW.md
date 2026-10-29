# End-to-end fixed-point review

Historical pre-conversion review, October 28, 2026. The subsequent fixed48
implementation supersedes the proposed design choices below; see NUMERICS.md
and VERIFICATION.md for the implemented backend and its limits.

Reviewed scope: all Forge source packages, the CLI and UI
contract, Ada/Python tests, build/verification configuration, numeric and
architecture documentation, and the pinned Bedrock vector implementation.

## Outcome

The production implementation is floating point throughout. The fixed-grid code
is independent prototype code; it is not selected by a flag or by the document
header. An end-to-end fixed-point implementation requires replacing the numeric
foundation and substantial parts of geometry, validation and serialization.
Changing `Scalar` alone cannot achieve this.

This document is a review and migration specification. It does not change the
runtime backend or claim that the migration is implemented.

## Findings, ordered by impact

### 1. Blocking: the public numeric foundation requires floating point

`src/forge.ads:12` derives `Scalar` from `Long_Float`. Mesh vertices, command
parameters, expression payloads, transforms, bounds and measures all use it.
The instantiated `Bedrock.Generic_Vectors` has a `digits <>` generic parameter,
which requires a floating-point type; its length operation calls floating-point
square root. It cannot be instantiated with an Ada fixed-point type unchanged.

Replace this instantiation with a Forge numeric/vector foundation. Separate
bounded coordinate storage from widened differences, cross products,
determinants and volume accumulators. Angles and scale factors need explicit
units and representations too; coordinate limits are not sufficient contracts
for dimensionless factors or intermediate quantities.

### 2. Blocking: Boolean construction is not closed over a fixed grid

`src/forge-csg.adb:90` classifies with normalized floating planes and epsilon;
line 127 divides to construct intersections; line 297 normalizes normals.
Reconstruction at line 349 creates polygon centroids by division, and line 365
uses floating projections and distances to repair shared edges.

An intersection of grid-aligned vertices with a plane is generally rational and
may not be a grid point. Independent coordinate rounding can move a vertex off
its supporting planes, break shared edges, or introduce self-intersections.
Centroids have the same representability problem even when the boundary is on
the grid. Exact predicates alone do not solve these construction problems.

`Forge.Fixed_Geometry.Split_Edge` rounds then checks one splitting plane. It does
not establish consistency with the source polygon plane or every neighboring
face, nor provide shared construction identity across a Boolean operation.
Its plane inputs also need a non-collinearity check before production use.

Required: integer plane predicates, canonical shared intersections, a declared
off-grid policy, and reconstruction that preserves coplanarity and edge pairing.
Prefer triangulation using existing boundary vertices over rounded centroid fans.
For a strict first implementation, reject unrepresentable constructions before
publishing any result. This will reduce supported geometry and must be explicit.
Preserving general rotated/cylinder cuts requires further qualification or a
topology-preserving grid construction algorithm; increasing precision alone
does not make a grid closed under intersections.

### 3. High: validation still requires floating elementary functions

`src/forge-validation.adb` uses normalized vectors, square roots, tolerant
barycentric tests and floating signed volume. Its shell containment test at
line 192 sums solid angles using `Arctan`. Replacing coordinate storage leaves
this entire decision path floating point.

Use exact integer orientation/collinearity/segment predicates and a deterministic
integer or rational-comparison containment test with explicit ray-edge/vertex
tie handling. Accumulate six times signed volume as widened integers; divide
only for presentation. Retain oriented edge pairing, vertex-fan checks,
self-intersection checks and shell orientation. Do not weaken validation to
accept rounded invalid geometry.

### 4. High: curved primitives and rotations have no integer implementation

`src/forge-primitives.adb:6` instantiates floating elementary functions for
cylinders. `src/forge-transform.adb:6` does the same for general rotations.
Box half-dimensions can also fall between ticks. Scaling can collapse edges or
produce off-grid coordinates.

Implement deterministic fixed-point trigonometry, such as integer CORDIC, with
specified coefficient precision and error bounds. Special-case quarter turns
as exact coordinate permutations. Round widened products once at the specified
boundary. Define centered odd-tick dimensions: either reject them or specify a
different placement policy. Validate quantized curved meshes and reject collapsed
faces and unsafe transforms. Any future sphere must follow the same policy.

### 5. High: parsing, persistence and export are floating too

`src/forge-commands.adb:111` parses through `Scalar'Value`; line 379 formats with
`Float_IO`. `src/forge-obj.adb:6` uses `Float_IO`. Session bounds, volume and
parameter responses must also use the new formatter. Save/load headers, OBJ
metadata and `info` explicitly identify the floating profile.

The prototype parser accepts only nine fractional digits and at most sixteen
characters. A 2^-16 mm tick is exactly `0.0000152587890625`, requiring sixteen
fractional digits. It cannot currently parse that canonical exact tick text.
It also does not accept the scientific notation emitted by the current command
formatter. Reusing it without changing grammar/formatting breaks persistence.

Implement checked decimal parsing and exact integer-to-decimal formatting as a
matched pair, with negative values, full coordinate range and documented exponent
support. Ensure `parse(format(tick)) = tick` for all supported ticks. For this
grid, sixteen fractional decimal places suffice for exact coordinate output.
Format signed volume from its separate numerator/denominator representation.

Give the new document format a versioned fixed-grid profile including resolution
and rounding policy. Reject old floating-profile files or convert them through
an explicitly named import operation; do not silently reinterpret them. Existing
headerless examples need a documented policy and regression coverage.

`src/forge-stl.adb:28` explicitly converts to IEEE binary32. Binary STL's numeric
fields are floating point. For a strict fixed-only project, remove this legacy
serializer and its public API/tests, keeping exact decimal OBJ export. Encoding
binary32 bits with integer instructions would still produce a floating format.

### 6. High: current tolerances and accumulator types cannot be reused

`Forge.Numeric.Epsilon` is 1e-8 mm, much smaller than a 2^-16 mm tick
(approximately 0.0000152588 mm). Validator thresholds include still smaller
dimensionless constants. Translating them mechanically into grid coordinates
can round them to zero and change classification or division behavior.

Use exact zero/sign tests for integer predicates and separately specified error
bounds for approximate constructions. Coordinate differences span twice the
coordinate domain. Products need widening before multiplication, not afterward.
The existing determinant bound fits signed 128 bits for the declared domain;
new products of determinants, squared normals and rational comparisons need their
own bounds or larger checked integers. A single universal fixed scalar is not
an adequate intermediate type.

### 7. Medium: existing tests/proofs do not establish fixed-only execution

Ada tests mostly exercise production `Scalar`, with a small isolated fixed-grid
test section. Python acceptance reads OBJ coordinates using `float`, expects
the floating profile and uses floating analytic cylinder references. The proof
gate selects fixed helpers, model structure, numeric bounds and history, not
Boolean or geometric correctness.

Add a fixed-only dependency/source gate; exact rational OBJ read-back; parser
round trips; positive/negative ties; coordinate and intermediate overflow;
odd-tick dimensions; rotations and scaling; representable and rejected off-grid
splits; centroid-free triangulation; repeated Boolean chains; and byte-identical
save/load and undo/redo. Reference expected cylinder volume from the actual
quantized operand vertices. Require the user-facing cube/cutter example to pass
or document a specific unsupported construction before release.

## Target numeric contract

- Coordinates: signed integer ticks, 65,536 ticks/mm, bounded to +/-10,000 mm.
- Exact predicates: unnormalized integer arithmetic with checked wide operands.
- Rounding: nearest, ties to even, only at named construction boundaries.
- Angles/factors: separate fixed representations, independent range contracts.
- Unsafe geometry: explicit failure, empty output cache, unchanged document/files.
- Serialization: decimal text computed using integers, exact tick round trips.
- Production closure: no floating scalar, `Float_IO`, floating vector generic or
  floating elementary function anywhere on the modeling execution path.
- Strict repository-wide closure: remove legacy float serializers; use rational
  acceptance checks too. External OBJ viewers are outside this arithmetic contract.

This preserves the current prototype's grid as a starting point. It does not
assert that its resolution is sufficient for every desired part.

## Implementation order and exit gates

1. Introduce the integer numeric foundation, checked widened operations, decimal
   parser/formatter and fixed angle/factor types. Prove/test ranges and rounding.
2. Migrate command records, trees, mesh storage, measures, bounds and persistence.
   Require exact text round trips and transactional profile handling.
3. Migrate boxes, transforms and cylinders. Require exact quarter turns,
   deterministic curved tessellation, and safe collapse/range failures.
4. Replace geometric validation with integer predicates and containment.
   Re-run all invalid-mesh, cavity and disconnected-shell cases.
5. Replace BSP planes, intersections and reconstruction. Qualify the off-grid
   policy against box, cylinder, rotated and chained Boolean fixtures.
6. Replace export/status formatting; retire binary STL; update documentation,
   metadata, CI and proof scope. Run the complete acceptance matrix and the
   fixed-only dependency gate on supported platforms.

Keep the existing session transaction, history and independent expression-tree
architecture. They already provide useful isolation and failure handling.
`Forge.Model`, `Forge.History` and the CLI's dispatch structure require little
algorithmic change; their numeric payloads and presentation still migrate.
Bounds need conservative outward rounding wherever approximation is introduced.

## Baseline verification actually run

`tools/verify.sh` completed successfully during this review:

- Library, Ada tests and CLI built with the configured checks.
- Ada regression executable reported all tests passed.
- Independent integration suite passed 1,708 assertions.
- SPARK flow passed 100 checks.
- Selected proof run passed 152 combined flow/proof checks.

The existing Bedrock unused-input warning remains. These results describe the
current floating production backend, not a completed fixed-point migration.
