# forge

Solid modeling with a proven topology kernel, driven by text. A CAD
engine you script, and a GUI that is a script generator.

GNAT Academic Program capstone project. Proposal title: *Forge: 3D CAD,
Solid Modeling with a Proven Geometry Kernel*.

## What it is

```
$ forge_cli
box base 60 8 40
ok
cylinder hole 4 10 24
ok
rotate hole x 90
ok
translate hole 15 0 0
ok
info hole
ok hole vertices 50 triangles 96 solid yes volume 4.969E+02 min ... max ...
difference cut base hole
ok
check cut
ok cut solid yes shells 1 genus 1 euler 0 ... open-edges 0 ... volume 18802.4539466808
export cut cut.stl
ok wrote 20884 bytes to cut.stl
save bracket.forge
ok saved 5 commands to bracket.forge
```

`genus 1` is the topology saying what the eye sees: one hole, all the
way through.

That transcript is the whole architecture:

- **The document is text.** A `.forge` file is the command history,
  one line per operation. There is no binary model format to keep in
  sync; the text is the model. Undo is "replay minus the last line".
- **One entry point.** `Forge.Session.Execute (S, Line, Response)`.
  The CLI feeds it stdin. A GUI feeds it the line it built when you
  clicked. An agent feeds it the line it reasoned to. All three get
  `ok` or `err reason` back, and can `info` anything.
- **The GUI cannot pollute the engine** because it has no other door.
  It renders `Mesh_Of (S, name)` (a read-only view) and sends lines.
  Everything the GUI can do, a script can do, by construction.
- **The kernel never allocates and never does I/O.** `Forge.Mesh` and
  below are SPARK-clean computations on meshes they are handed.
  `Forge.Session` owns memory; `cli/` and `ui/` own files and screens.

"Proven geometry" in year one means proven **topology**: a solid is a
closed, consistently oriented triangle mesh, `Is_Solid` says so, and
every kernel operation promises solid in, solid out. Coordinates are
fixed point on a 2**-32 mm grid, and the booleans decide which side of
a plane a point is on with exact integer arithmetic (`Forge.Exact`):
the geometry is not proven yet, but it is now the kind that can be.

## What is in the seed

```
src/forge.ads             Scalar, Vec3, Axis, Name                          Pure, SPARK
src/forge-mesh.ads        Tri_Mesh, Well_Formed, Is_Watertight, Volume      SPARK, proof target
src/forge-primitives.ads  Box, Cylinder (solid, centred)                    done
src/forge-transform.ads   Translate, Rotate, Scale                          done
src/forge-exact.ads       exact integer plane tests on the fixed-point grid  done
src/forge-validity.ads    fast solid check: shells, genus, open edges, ...  done (M1)
src/forge-csg.ads         Union, Difference, Intersection + result repair   done (M2, BSP)
src/forge-stl.ads         binary STL writer                                 done
src/forge-commands.ads    the grammar: Parse <-> Image, round-trips         done
src/forge-session.ads     named solids, history, undo, save/load, Execute   done
cli/                      REPL, file runner, -c one-liners; exit = failures  done
ui/README.md              the contract for the GUI (adi2 + OpenGLAda)        contract only
examples/bracket.forge    an L bracket: wall fused on, hole drilled through
tests/                    131 checks: topology, fixed point, exact tests, validity, CSG, session
```

Everything runs, booleans included. What is left of the capstone is
making them robust (milestone 4) and everything above them.

Read `ARCHITECTURE.md` before touching anything.

## Milestones

1. **Faster `Is_Watertight`.** Done as `Forge.Validity.Inspect`:
   directed edges sorted, O(NT log NT), and it also catches the
   "bowtie" vertex the edge test cannot see. `Is_Watertight` stays as
   the O(NT^2) reference; the tests check the two agree. Proving the
   fast one equal to the reference is still open.
2. **BSP-tree CSG.** Done: csg.js, plus a repair pass (weld, T-joints,
   spike removal, fan) so the output is an indexed solid. The bracket
   in `examples/` is a real part. Where two solids only touch along a
   line or at a point, the honest answer is not a solid, and the
   kernel says so instead of returning one.
3. **Extrude.** A 2D polygon along Z. Second primitive, first one
   with user-supplied topology, so the "solid out" promise has to be
   checked, not assumed.
4. **Robust CSG.** Exact predicates on the intersection curve so that
   `Is_Solid` holds on the output for every input pair. This is where
   "proven" gets teeth, and it is a year-two topic if year one lands
   milestone 2 well.
5. **The GUI.** See `ui/README.md`. adi2 window, OpenGLAda viewport
   in a texture view, a command line at the bottom that shows every
   line the buttons generate. Not before milestone 2.

## Build

Three [Alire](https://alire.ada.dev) crates; cli and tests pin the
library by path.

```
alr build
cd tests && alr build && ./bin/tests
cd cli   && alr build && ./bin/forge_cli ../examples/bracket.forge
alr with gnatprove && alr exec -- gnatprove -P forge.gpr --mode=flow
```

Contracts are checked at runtime (`-gnata`). Warnings are errors.

## Driving it from anything

Because the protocol is lines in, lines out:

```
echo "box b 1 2 3" | forge_cli
forge_cli -c "load part.forge" -c "info body" -c "export body body.stl"
python: subprocess.Popen(["forge_cli"], stdin=PIPE, stdout=PIPE)
```

An MCP server that exposes `execute(line)` and `history()` is an
afternoon, and then an agent designs parts by talking to the same
engine the GUI uses. That is the 2026 answer to AutoLISP.

## Rules of the road

- `src/` below `Forge.Session` has no I/O and no allocation.
- Every kernel operation: solid in, solid out, or `Ok = False` with a
  reason. Never a mesh that fails `Is_Solid` handed back as a result.
- Every new modeling command gets a `Parse` case, an `Image` case, a
  round-trip test, and a line in the grammar comment. No command
  exists that the text cannot express.
- Nothing in `ui/` or `cli/` withs anything below `Forge.Session`.

See `CONTRIBUTING.md` for the fork workflow.

## Contact

Olivier Henley, GAP Coordinator, AdaCore. Weekly meeting, plus the
project Discord.

## License

Apache-2.0. See `LICENSE`.
