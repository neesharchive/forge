# Numerical implementation decision

Production BSP remains floating point. `Forge.Scalar` derives from `Long_Float`;
actual representation is compiler/target dependent. Inputs and evaluated vertices
are bounded to +/-10,000 mm. Plane classification and positional reconstruction use
1e-8 mm tolerance; no universal error bound or arbitrary-scale robustness is
claimed. Mesh validation rejects output when closure, manifoldness, embedding or
shell orientation fails. Nearly coincident features can produce a precision or
validation failure and must not be silently healed.

The initial requirements proposed a scale-derived tolerance policy. This release
uses a single qualified bounded-domain positional tolerance instead; separate
angular/barycentric thresholds occur in the validator. Expanding the coordinate
range or supporting finer features requires additional qualification. The tested
release corpus is evidence for the included examples, not for all geometry in the
declared range.

## Fixed grid implementation

`Forge.Fixed` uses signed integer ticks at 2^-16 mm with a symmetric +/-10,000 mm
domain. Quarter turns are coordinate permutations/sign changes. Translation is
computed in widened integer intermediates and commits only when all sums fit.
Integer division rounds nearest, ties to even for either sign.

`Forge.Fixed_Geometry` parses plain decimal millimetres directly to rational
integers before quantization. It accepts up to nine fractional digits, rejects
out-of-range input and does not pass through a binary float. Exact plane predicates
use an unnormalized determinant in a signed 128-bit type. Coordinate differences
are at most 1,310,720,000 ticks; the conservative determinant bound is
6 * 1,310,720,000^3, below 2^94. Split interpolation numerators also fit signed 128
bits for the bounded, opposite-side endpoints used by the algorithm.

An edge-plane intersection is usually rational. The prototype rounds the result
to ticks, reclassifies it exactly and rejects it unless it remains on the splitting
plane. This gives a safe local failure mode; it does not establish consistency
with every neighboring plane and is therefore not a production mesh Boolean
backend. The tests include both representable and unsafe half-grid intersections.
General rotation and tessellated curved primitives still need an approximation
policy; a fixed-point production backend has not passed the release gate.

Single quantization error is at most q/2 per coordinate. Repeated construction
error cannot be described by that single-step bound. Exact predicates and exact
constructions are separate issues.

## Export

The requested format is OBJ. Positions are written with `Scalar'Digits + 2`
fractional digits in scientific notation, enough to round-trip the current scalar.
The independent reader checks the resulting mesh. OBJ has no mandatory binary32
conversion. Unit convention is millimetres.

## Proof scope

The arithmetic in `Forge.Fixed` and the bounded comparisons in `Forge.Numeric`
are SPARK proof targets. The decimal parser and 128-bit construction prototype are
tested Ada outside SPARK. They are not described as formally proved. See
`VERIFICATION.md` for exact commands/results.
