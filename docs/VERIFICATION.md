# Fixed48 verification evidence

Verified October 28, 2026 on macOS ARM64 with GNAT 16.1.0, GNATprove 16.1.0
and GPRbuild 26.0.1. The complete `tools/verify.sh` release gate exited zero.
The script selects the installed macOS 15 SDK locally for linker compatibility.
Linux/macOS CI now runs the same fixed-point gates; remote CI results are not
claimed here.

## Executed results

| Gate | Result |
|---|---|
| Library, Ada tests and CLI builds | Pass with assertions, style checks and warnings as errors |
| Ada regression suite | 199 checks pass |
| Exact-rational CLI/document/OBJ integration | 1,811 assertions pass |
| Fixed-only source/object and end-to-end acceptance | 91 checks pass |
| Bracket Boolean qualification | 24, 64, 128 and 256 segment cylinders pass |
| Whole-project SPARK flow | 99 checks pass; zero unproved |
| Selected SPARK proof run with forced analysis | 189 combined checks pass; zero unproved |

The final combined report contains 99 flow checks and 90 prover checks, including
70 runtime checks, 17 functional-contract checks and three prover termination
checks. These counts are not independent geometric theorems. The new production
`Forge.Grid` contributes 35 successful prover checks in the detailed report.
The unchanged Bedrock `Buffers.Fill` unused-input warning remains.

Current evidence:

- [Complete successful run](verification/fixed48-full-run.log)
- [Detailed proof report](verification/fixed48-gnatprove.out)
- [Source SHA-256 snapshot](verification/fixed48-sources.json)

The other logs and `benchmarks.json` predate conversion and describe the previous
floating backend. They are historical evidence, not current performance claims.

## New SPARK scope

`Forge.Grid` is used by production translation, scaling and quarter-turn mesh
rotation. Its proved properties include:

- Exact fixed-coordinate/integer-tick round trips within +/-10,000 mm.
- Translation arithmetic safety, exact successful sums and unchanged failure state.
- Exact squared-distance preservation under quarter turns on each axis.
- Wide-product range safety for scaling.
- Rounded-quotient error at most half a tick, with even results at exact ties.
- Successful scaling equals that rounded quotient; failed scaling preserves input.

The selected proof command also retains `Forge.Fixed`, `Forge.Numeric`,
`Forge.Model` and `Forge.History`. No `pragma Assume`, suppressed checks or weakened
proof contracts were added to obtain these results.

The complete Boolean algorithm is not formally proved. Root elementary functions,
BSP clipping/reconstruction, geometric validation, parsing/formatting, session
I/O and compatibility STL encoding are tested Ada outside SPARK. Whole-project
flow checks the SPARK portions only. In particular, the accuracy of the Taylor
approximations and arbitrary-mesh Boolean correctness are not proof claims.

## Independent arithmetic and geometry checks

`tests/integration.py` reads OBJ using exact Python fractions. It checks indexed
triangle connectivity, reverse edge pairs, bounds, box volumes and bracket volume
against the actual quantized cutter. Save/load and undo/redo preserve OBJ bytes.
Failed loads, evaluations and exports preserve the required document/file state.

`tests/fixed_point.py` bans floating types/libraries in Forge source and numeric
floating instructions/conversions in compiled Forge objects using `otool` on
macOS or `objdump` on Linux. It checks exact grid membership, one-tick export,
positive/negative tie quantization, profile rejection, exact replay, noncardinal
rotations against an independent rational Taylor series, and all four bracket
qualifications. This audit covers Forge objects and the modeled numeric path;
it does not claim that unrelated linked runtime or Bedrock code has no floats.

Ada checks additionally cover 2,000 generated exact tick text round trips,
coordinate endpoints, translation/scaling overflow, quarter-turn cycles, square
roots, trigonometric quadrants, integer-only binary STL encoding, the user's
20 mm cube/6 mm radius cutter example, invalid geometry and failed bounds queries.

## Reproduce

```sh
tools/verify.sh
```

The script builds all three projects, runs both Python suites and the Ada tests,
then executes:

```sh
alr -n exec -- gnatprove -P forge.gpr --mode=flow --checks-as-errors=on
alr -n exec -- gnatprove -P forge.gpr --mode=prove --level=2 -f \
  --checks-as-errors=on -u forge-fixed.adb forge-grid.adb forge-model.adb \
  forge-numeric.ads forge-history.adb
```

General rotations and Booleans remain tolerance-based fixed-point approximations.
Validated output and bounded failures do not imply exact analytic CAD geometry.
See [numeric policy](NUMERICS.md) for representation, rounding and compatibility.
