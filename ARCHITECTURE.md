# Architecture

## Layers

```
ui/  (adi2 + OpenGLAda)      cli/  (stdin)         an agent (pipe)      front ends: lines in, lines out
              \                 |                    /
               Forge.Session    Execute (S, Line, Response); Mesh_Of for renderers
                    |           owns memory (heap), history, undo, save/load
               Forge.Commands   Command <-> text, Parse and Image are inverses
                    |
   Forge.CSG   Forge.Primitives   Forge.Transform   Forge.STL      kernel operations
       |
   Forge.Validity    fast solid check and diagnosis (shells, genus, open edges, ...)
                    |
               Forge.Mesh        Tri_Mesh, Well_Formed, Is_Watertight, Volume    SPARK, proof target
                    |
               Forge             Scalar, Vec3, Name                              Pure
```

Dependencies point down only. Nothing above `Forge.Session` names a
kernel package. Nothing at or below `Forge.Mesh` allocates or does I/O.

## The edge, and why it holds

Every CAD program has a script layer bolted on after the fact, and the
GUI always ends up able to do things the script cannot. forge inverts
the order: the script layer is the only layer. `Forge.Session.Execute`
takes a `String` and returns a `Response`. There is no second API.

Consequences:

- A GUI button is a function that builds a line and calls `Execute`.
  The GUI's command bar shows that line. A user learns the language by
  watching the buttons.
- The document is the history. Save writes it; load replays it. There
  is no serializer to keep in sync with the model, because the model
  is a replay.
- Undo is pop-and-replay. O(n), and there is nothing to get wrong.
- An agent has the same power as a user: read the file, emit lines,
  read `info`. No screenshot parsing, no accessibility tree.

The cost: replay must be deterministic. The kernel is pure, so it is.

## Kernel

### Tri_Mesh

Indexed triangle mesh, bounded by two discriminants, no heap. `NV`,
`NT` live counts; `V (1 .. NV)`, `T (1 .. NT)`. `Well_Formed` says every
triangle refers to three distinct live vertices; it is the
precondition of everything and the postcondition of every builder.

### Solid

A mesh is a solid when it is closed and consistently oriented. One test
covers both: every directed edge `(a, b)` appears exactly once and its
reverse `(b, a)` appears exactly once. That is `Is_Watertight`. A hole
breaks "once"; a flipped triangle breaks "reverse". `Is_Solid` adds
`NT >= 4` (a tetrahedron is the smallest closed surface).

`Volume` is the signed sum over triangles of `dot (a, cross (b, c)) / 6`.
Positive for outward orientation. The tests use it as a second oracle.

`Is_Watertight` compares every edge with every other: O(NT^2), kept as
the reference definition. `Forge.Validity.Inspect` gives the same answer
in O(NT log NT) by sorting the directed edges, and goes further. It
finds vertices where two cones of triangles meet at a point (a
"bowtie"), which pass the edge test but are not a solid, and it reports
shells, genus (through-holes, from Euler's V - E + F), open and repeated
edges, slivers, area and volume. Its `Solid` is the stricter test:
watertight, one fan of triangles at every vertex, at least four
triangles, positive volume. Like the kernel, it does not allocate: the
caller hands it a `Workspace`.

### Numbers

`Scalar` is binary fixed point: a whole number of 2**-32 mm steps,
128 bits wide, with coordinates kept within `Coordinate_Limit` (10 m).
Every value is an integer underneath, so a question about it can be
answered exactly, which is what robust booleans and a proof both need.

The kernel never leaves the grid. Conversion to anything else happens
at the edge, in the code that needs it: `Forge.STL` turns steps into
float32 because the STL format says so, and another exporter (OBJ, a
renderer's vertex buffer) does its own conversion the same way. So no
file format, and no display, decides what the kernel computes.

### Operations

Primitives build a mesh from nothing and promise `Is_Solid`. Transforms
move vertices and leave topology alone, so they preserve `Is_Solid` by
construction (except a negative scale, which the spec forbids). CSG
combines two solids into a third (below). STL is a byte writer.

Every operation has the same shape: meshes in, mesh out, `Ok` out, and
in CSG a reason. No exceptions cross a kernel boundary.

## Session

`Solids`: a fixed table of 64 named `Mesh_Access`, allocated once per
slot at first use and reused. `History`: 4096 modeling commands.
`Execute` parses, dispatches, and for modeling commands appends to the
history only on success, so the history is always replayable.

`Ensure_Solid` after every primitive and CSG result: if the kernel hands
back something that fails the solid check (`Forge.Validity`), the
session discards it and reports why. The kernel's promise is checked at
the boundary, which is what lets `ui/` trust `Mesh_Of` blindly.

The session also owns the kernel's scratch memory: one validity
workspace, allocated on first use, and one workspace per boolean, sized
to its inputs and grown fourfold (twice at most) if the kernel reports
it full. A boolean is computed into a scratch mesh and then copied into
place, so `difference base base hole` cuts `base` in place.

## Commands

A `Command` is a discriminated record; `Parse` builds one from a line,
`Image` prints it. The grammar is in the spec header. Numbers print as
the exact decimal of their grid value (at most 32 digits after the
point, since 2**-32 needs exactly 32), so files are readable and still
exact. `Round_Trip` in the tests is the contract.

Queries (`list`, `info`), side effects (`export`) and meta commands
(`undo`, `save`, `load`) are not recorded. Only `Modeling` commands
are the document.

## CSG: the project

`Forge.CSG.Apply (Op, A, B, Result, Work, Check, Status, Reason, Last)`.
The contract is solid in, solid out, or `Status /= Success` with a
reason and an empty `Result`.

### What is built (milestone 2)

**BSP CSG**, the csg.js algorithm. Each solid becomes a BSP tree of its
face planes. "Clip X by Y" sends X's polygons down Y's tree, cutting
them where they cross a plane, and drops the pieces that end up inside
Y. Union is: clip A by B, clip B by A, then clip B's inverse by A to drop
the faces the two share, so a shared face is kept once. Difference and
intersection are the same moves around inversions (De Morgan). The
trees are walked with an explicit stack: no recursion, no heap.

Two things keep the BSP from shredding curved solids. Every plane of a
BSP extends forever, so a polygon far from the other solid would be cut
by planes that never touch it: polygons clear of the other solid's
bounding box skip the cutting. And the polygons enter each tree in a
shuffled order (a fixed seed, so replay is exact), because a cylinder's
walls in order around the axis each shave one sliver off a crossing
triangle, where a random order removes most of it in a few cuts. Two
256-segment pipes went from "out of memory" to three booleans in 8 s.

**Exact on the grid** (`Forge.Exact`). The BSP never sees a `Scalar`:
coordinates are converted to whole step counts on the way in and back
on the way out. A plane is an exact normal (the cross product of two
edges of an input triangle, 128-bit) and a point on it, and pieces cut
from a polygon keep that plane exactly.

Which triangle gives the plane matters once booleans are chained: an
earlier boolean leaves needle triangles whose corners are almost in a
line, so their own plane points almost anywhere. Each input triangle
takes the plane of the largest triangle across its edges that holds all
its corners, the face it really lies in (`Face_Planes`). "Which side of
the plane is P" is the sign of N . (P - A), about 142 bits, carried as
a high/low pair of 128-bit integers like long multiplication carries
digits: the true sign, the same from every point of the plane, the same
on every machine. The test suite shows a point one grid step (0.23
picometres) off a tilted plane 20 m out being seen as off it.

The one rounding is where a cut makes a new point: an edge crosses a
plane between grid points, and `Exact.Crossing` rounds to the nearest
one. It always works from the same end of the edge, so the two polygons
sharing the edge make the same point, bit for bit. The cost of all this
is speed: a side test is long multiplication, not one float multiply,
and the 256-segment case above takes about twice as long as in floating
point.

**Repair**: the BSP's output is a soup of convex polygons, and it
becomes an indexed solid in five steps.

1. Weld: points within the weld tolerance are one vertex. A point
   reached by two different chains of cuts can land a few steps away
   from itself.
2. T-joints: a vertex lying on the middle of a neighbour's edge is
   inserted into that edge, so both sides of every edge carry the same
   vertices. A binary search along a sort direction finds candidates.
3. Clean: drop repeated vertices, and fold away "spikes" (x, y, x: out
   to y and straight back), which T-joint insertion leaves where a
   polygon had collapsed to a line.
4. Fan: an outline welding pinched into a figure 8 is first cut in two
   at the repeated vertex. Strictly convex outlines are fanned from a
   corner, others from their centre, so no zero-area triangle is made.
5. Check: `Forge.Validity` must say `Solid`, or `Apply` fails.

**Tolerances** are counts of grid steps, set by the rounding they
absorb, not by the size of the part: a point within about 64 steps (15
picometres) of a plane is on it, since a cut point sits up to half a
step off the plane that made it, a little more after several cuts;
points within 1024 steps (a quarter of a nanometre) on every axis are
welded. Every test is an integer comparison.

The exact arithmetic is proven overflow-free for coordinates within
2**47 steps (about 32.7 m, three times `Coordinate_Limit`); `Apply`
refuses anything beyond that (`Out_Of_Range`) rather than risk it.

### What it refuses, and why that is right

Two cubes touching at one corner, two equal pipes crossing (they touch
at two points), a pipe whose radius equals the half-width of the box it
is cut from (it touches the faces along four lines): in each case the
exact answer has zero thickness somewhere, and no closed triangle mesh
can hold it. `Apply` says "result pinches to an edge or a point" rather
than hand back something that is not a solid. Near tangency the same
refusal can read "result has a crack". Either message can also be a
robustness failure: see the last limit below.

### Known limits

- Output has more triangles than it needs: faces are cut along the
  other solid's planes and never merged back. Coplanar fragments could
  be re-triangulated per original face; not done.
- Building a tree is O(n^2) in the worst case (a chain of planes).
  Fine for primitives and a few booleans deep; a long chain of booleans
  on high-segment cylinders will slow down.
- The side test is exact, but rounding cut points to the grid means
  the tests still need a small tolerance, and so does the repair. Deep
  in a chain of booleans on one part, a sliver can get as thin as the
  weld tolerance; neighbouring polygons then disagree on whether a point
  is on their edge, and a good answer is refused. The flange cut one
  feature at a time gets 16 booleans deep. It is an error, never a bad
  solid; until milestone 4, join repeated features into one solid and
  cut once, as `examples/flange.forge` does.

### Next: robustness (milestone 4)

What is left is the rounding of cut points. The way to remove it is to
never round them: keep a cut point as the intersection of three planes
(plane-based geometry, as in Campen and Kobbelt's exact mesh booleans)
and decide its side of a fourth plane exactly. That test needs a
4 x 4 determinant, a few hundred bits, so `Wide` grows into a small
fixed-size big integer; the tolerances then go to zero, and with them
the last reason a correct input could give a wrong answer. That is
also the version worth proving.

What must never happen: `Apply` returning `Success` with a mesh that
fails the solid check. It checks itself; the session checks again.

## STL

Binary STL, 84 + 50 * NT bytes, little-endian, face normal unnormalized
(readers ignore it). `Size` is exact; `Write` fills exactly that. Export
is derived data; the `.forge` file is the source.

## What is deliberately not here

- Parametric constraints, sketches, fillets. Each is a command family
  on top of this; none changes the architecture.
- Any mesh import. STL in is a milestone once CSG can consume arbitrary
  solids.
- A GUI in the seed. `ui/README.md` is the contract; adi2 and OpenGLAda
  are the tools; milestone 5.
