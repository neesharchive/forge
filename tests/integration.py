#!/usr/bin/env python3
"""Independent CLI, document and Wavefront OBJ acceptance checks (stdlib only)."""
import collections
from fractions import Fraction
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / 'cli/bin/forge_cli'
checks = 0


def check(condition, message):
    global checks
    assert condition, message
    checks += 1
    if message != 'OBJ triangle indices valid':
        print('PASS ', message)


def run(lines, expected_errors=0):
    result = subprocess.run([str(CLI)], input='\n'.join(lines) + '\n',
                            text=True, capture_output=True, cwd=ROOT, timeout=60)
    replies = result.stdout.splitlines()
    errors = [line for line in replies if line.startswith('err ')]
    check(result.returncode == expected_errors and len(errors) == expected_errors,
          'CLI status matches expected errors: ' + str(errors))
    check(len(replies) == len(lines), 'one response per command')
    return replies


def obj(path):
    vertices, faces = [], []
    for line in path.read_text().splitlines():
        words = line.split()
        if not words or words[0].startswith('#'):
            continue
        if words[0] == 'v':
            vertices.append(tuple(map(Fraction, words[1:])))
        elif words[0] == 'f':
            faces.append(tuple(int(w.split('/')[0])-1 for w in words[1:]))
        else:
            check(words[0] in ('o', 's'), 'recognized OBJ metadata')
    check(bool(vertices) and bool(faces), 'OBJ has vertices and faces')
    check(all(len(v) == 3 and all(isinstance(c, Fraction) for c in v) for v in vertices),
          'OBJ coordinates finite')
    edges = collections.Counter()
    volume = 0
    for face in faces:
        check(len(face) == 3 and len(set(face)) == 3 and
              all(0 <= v < len(vertices) for v in face), 'OBJ triangle indices valid')
        a, b, c = (vertices[v] for v in face)
        cross = (b[1]*c[2]-b[2]*c[1], b[2]*c[0]-b[0]*c[2], b[0]*c[1]-b[1]*c[0])
        volume += sum(a[i]*cross[i] for i in range(3))/6
        for i in range(3):
            edges[face[i], face[(i+1) % 3]] += 1
    check(all(n == 1 and edges[b, a] == 1 for (a, b), n in edges.items()),
          'OBJ closed with opposite oriented twins')
    bounds = tuple((min(v[i] for v in vertices), max(v[i] for v in vertices)) for i in range(3))
    return vertices, faces, volume, bounds


with tempfile.TemporaryDirectory(prefix='forge-check-') as directory:
    folder = Path(directory)
    bracket = folder / 'bracket.obj'
    saved = folder / 'saved model.forge'
    again = folder / 'again.obj'
    bad = folder / 'bad.forge'
    side_effect = folder / 'must-not-exist.obj'
    bad.write_text('box changed 1 1 1\nexport changed ' + str(side_effect) + '\n')
    replies = run([
        'load examples/primitives.forge',
        'union bracket base wall', 'difference cut bracket hole', 'evaluate cut',
        f'export cut {bracket}', f'save "{saved}"', 'tree cut',
        'undo', 'redo', f'export cut {again}',
        f'load {bad}', 'info cut', f'load "{saved}"', f'export cut {again}',
    ], expected_errors=1)
    check(not side_effect.exists(), 'document cannot execute export side effects')
    check('cut profile fixed48' in replies[11], 'failed load preserves original model')
    check(bracket.read_bytes() == again.read_bytes(), 'undo/redo and save/load preserve OBJ bytes')
    vertices, faces, volume, bounds = obj(bracket)
    cutter = folder / 'cutter.obj'
    run(['load examples/primitives.forge', f'export hole {cutter}'])
    _, _, cutter_volume, _ = obj(cutter)
    expected = 35200 - cutter_volume * Fraction(8, 10)
    check(abs(volume - expected) <= abs(expected) / 10**11, 'bracket volume matches polygonal hole')
    check(bounds == ((-30, 30), (-4, 54), (-20, 20)), 'bracket OBJ bounds correct')
    print(f'Bracket: {len(vertices)} vertices, {len(faces)} triangles, volume {volume.numerator}/{volume.denominator}')
    previous = bracket.read_bytes()
    replies = run(['box a 2 2 2', 'difference e a a', f'export e {bracket}',
                   f'export a {folder / "bad.stl"}', 'box', 'save', 'load',
                   'box bad -1 1 1', 'scale a 0', 'info a'], expected_errors=7)
    check(bracket.read_bytes() == previous, 'failed empty export preserves existing destination')
    check(not (folder / 'bad.stl').exists(), 'export rejects non-OBJ format')
    check('solid yes' in replies[-1], 'parse failures leave model usable')
    replies = run([f'box a{i} 1 1 1' for i in range(64)] +
                  ['box overflow 1 1 1', 'list'], expected_errors=1)
    check('overflow' not in replies[-1] and 'a63' in replies[-1],
          'named-object capacity failure preserves prior objects')
    run(['box a 1 1 1'] + ['translate a 0 0 0']*129 + ['info a'], expected_errors=1)
    mismatch = folder / 'profile.forge'
    mismatch.write_text('# forge-format 1 numeric fixed\nbox b 1 1 1\n')
    run(['box a 1 1 1', f'load {mismatch}', 'info a'], expected_errors=1)
    for offset in ('0.25', '0.75', '1.5'):
        out = folder / 'cut.obj'
        run(['box a 2 2 2', 'box b 2 2 2', f'translate b {offset} 0 0',
             'difference d a b', f'export d {out}'])
        _, _, measured, _ = obj(out)
        check(abs(measured - 4*Fraction(offset)) <= Fraction(1, 10**10), 'parametric box difference volume')
    bounds = run(['box a 4 2 2', 'rotate a z 90', 'bounds a',
                  'difference e a a', 'bounds e', 'evaluate e'])
    check(bounds[2].startswith('ok conservative min'), 'symbolic transformed bounds available')
    check(bounds[4].startswith('ok conservative min') and bounds[5] == 'ok empty',
          'conservative subtraction bounds distinguished from empty evaluated result')
    run(['box a 2 2 2', 'box b 1 1 1', 'rotate b z 31',
         'translate b 0.8 0 0', 'difference d a b', 'evaluate d'])
print(f'{checks} integration assertions passed')
