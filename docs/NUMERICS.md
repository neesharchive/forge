# Production fixed-point arithmetic

Forge's production scalar is an Ada ordinary fixed-point type with `Small =
2^-48` mm and 128-bit storage. Its declared scalar range is -2^63 through
2^63-1; the much smaller public coordinate domain remains +/-10,000 mm.
Vectors, command/expression payloads, meshes, transforms, BSP planes and
intersections, validation, bounds and volume calculations use this type.
Bedrock's floating-only vector generic is no longer instantiated.

This is fixed-point approximate polygonal geometry, not an exact rational Boolean
kernel. A grid is not closed under general edge/plane intersection. Coordinates
are quantized; geometric decisions use the declared tolerance and output is
validated. An unsuccessful evaluation clears the derived mesh. No floating-point
fallback is used when a construction fails.

## Arithmetic and rounding

`Forge.Grid` stores production coordinates as signed 64-bit integer ticks at
281,474,976,710,656 ticks/mm. The coordinate limit is 2,814,749,767,106,560,000 ticks.
Translation sums fit the underlying signed 64-bit type even before domain checks.
Quarter turns permute/negate coordinates exactly for every axis. Scaling widens
both operands before multiplication to signed 128 bits, divides once by 2^48,
rounds nearest/ties-to-even, and commits only when the result remains in range.
The maximum product magnitude is `Limit^2`, below 2^123. Squared three-dimensional
coordinate norms fit signed 128 bits too.

Other geometry operations use GNAT's checked ordinary fixed-point multiplication
and division. On the qualified GNAT 16 target these use integer arithmetic and
truncate toward zero at the scalar precision boundary. They do not promise the
same rounding rule as input or `Grid.Scale`. Each intermediate has explicit fixed
typing; coordinate-sized values are not used as product accumulator types.
Range failures are reported, rather than wrapped or saturated. SPARK proofs cover
the selected `Grid` operations, not all intermediate bounds throughout BSP.

## Text boundaries and documents

`Forge.Text.Parse` accepts plain optional-sign decimal syntax with up to 64
fractional digits. It bounds the integral part before accumulation, then extracts
48 fraction bits and a guard bit by decimal long division. Remaining digits act
as sticky bits. Input is rounded once to nearest/ties-to-even without passing
through a floating scalar. Values outside the coordinate/parameter domain are
rejected before rounding. Exponents, underscores and based literals are rejected.

`Forge.Text.Number` writes the exact integer part and terminating decimal
fraction. Every stored scalar fraction terminates within 48 fractional decimal
digits. Canonical zero is `0`, including inputs that round to zero. The same
formatter supplies history, parameter inspection, status, bounds, volumes and OBJ.
Parsing and formatting are tested outside SPARK, including exact ties of both
signs, endpoints and 2,000 generated tick round trips.

Saved files declare `# forge-format 1 numeric fixed48`. Other profile headers,
including the former `floating`, are rejected transactionally. Headerless scripts
are interpreted in the active fixed48 profile. Converting an old floating-profile
file must be deliberate: replay its modeling lines as a new script, review the
quantized result, and save a new file. Old geometry is not promised identical.

## Elementary functions and geometry

`Forge.Sin_Cos` performs fixed-point degree range reduction, exact cardinal-angle
handling and 16 Taylor correction terms on a reduced angle. Pi is stored as an
integer multiple of the quantum. General rotations and cylinders use this path;
quarter-turn mesh transforms use the proved integer permutation directly.

Vector length scales by the largest component before computing a norm. The
normalized square-root radicand lies in [1,3]. Its fixed-point square root uses
integer Newton iteration on a widened radicand, returning a floor at the scalar
quantum. The general `Sqrt` helper uses fixed Newton iteration above four.
`Atan2`, used by shell containment, uses fixed-point quadrant/range reduction
and 24 Taylor correction terms. These functions are bounded-loop tested Ada;
there is no formal approximation-error proof for them.

The positional tolerance is exactly 2^-27 mm, approximately 7.45e-9 mm, above the
scalar quantum (approximately 3.55e-15 mm). Angular/barycentric tests use exact
binary constants. Segment/triangle parallel testing includes an absolute error
floor derived from fixed cross/dot rounding, and scales the relative angular
bound using the original edge lengths before cross-product cancellation.
Axis-plane split coordinates are reset to the exact plane coordinate. Polygon
centroids are computed by summing before division, preserving constant-coordinate
planes exactly. Very small/collapsed or ambiguous geometry can fail; a quantum is
storage resolution, not a guaranteed minimum supported feature size.

## Export and compatibility

The session exports exact decimal OBJ coordinates with `profile fixed48`
metadata. The independent reader uses Python `Fraction`, checks grid membership,
connectivity, bounds, volume and replay bytes. Cylinder-cut volume is compared
with the actual quantized operand rather than an ideal floating sine formula.

The legacy standalone binary STL serializer still writes IEEE binary32 fields,
as required by that format. Its conversion and ties-to-even bit encoding are
implemented with integers; it uses no floating-point arithmetic. Binary STL is
lossy on disk and is not the precision-preserving session export format.

The old `Forge.Fixed` and `Forge.Fixed_Geometry` packages retain a separate
2^-16 mm experiment, including exact 128-bit predicates and local off-grid split
rejection. They are not the current grid or a second production backend.

## Verification boundary

`tools/verify.sh` builds the library, Ada tests and CLI, runs exact-rational
integration tests and fixed-only source/object instruction checks, qualifies
24/64/128/256-segment bracket cuts, and runs SPARK flow and selected proofs.
`Forge.Grid` proves exact coordinate conversion round trips, range safety,
translation results and failure preservation, quarter-turn norm preservation,
rounded quotient error <= half a tick with even ties, and checked scaling.

The source/object gate checks Forge units; it does not claim that all unrelated
code linked from the Ada runtime or Bedrock contains no floating types. No
floating type or arithmetic is used on the modeled numeric path. The compiled
Forge object gate bans numeric floating instructions and conversions on the
available target. See VERIFICATION.md for executed platforms and proof scope.
