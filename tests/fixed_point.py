#!/usr/bin/env python3
"""Fixed-only source/object gate and independent exact-rational acceptance."""
from fractions import Fraction as F
from itertools import product
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / 'cli/bin/forge_cli'
Q = F(1, 2**48)
checks = 0


def check(condition, message):
    global checks
    assert condition, message
    checks += 1
    print('PASS ', message)


def run(lines, errors=0):
    result = subprocess.run([str(CLI)], input='\n'.join(lines) + '\n', text=True,
                            capture_output=True, cwd=ROOT, timeout=180)
    check(result.returncode == errors and
          sum(line.startswith('err ') for line in result.stdout.splitlines()) == errors,
          'fixed CLI command outcomes: ' + result.stdout[-180:])
    return result.stdout


def vertices(path):
    return [tuple(map(F, line.split()[1:])) for line in path.read_text().splitlines()
            if line.startswith('v ')]


def decimal(value):
    # Exact decimal for a binary rational, including half-tick inputs.
    sign = '-' if value < 0 else ''
    n, d = abs(value.numerator), value.denominator
    whole, rem = divmod(n, d)
    digits = ''
    while rem:
        digit, rem = divmod(rem * 10, d)
        digits += str(digit)
    return sign + str(whole) + ('.' + digits if digits else '')


def reference_trig(degrees):
    pi = F('3.1415926535897932384626433832795028841971693993751058209749445923')
    degrees = (degrees + 180) % 360 - 180
    a = degrees * pi / 180
    st, ct = a, F(1)
    sine, cosine = st, ct
    for i in range(1, 60):
        st *= -a*a / ((2*i)*(2*i+1))
        ct *= -a*a / ((2*i-1)*(2*i))
        sine += st
        cosine += ct
    return sine, cosine


# Strip Ada comments so explanations of the retired implementation are allowed.
for source in sorted((ROOT / 'src').glob('*')):
    if source.suffix not in ('.ads', '.adb'):
        continue
    code = '\n'.join(line.split('--', 1)[0] for line in source.read_text().splitlines())
    check(not re.search(r'\b(?:Float|Long_Float|Long_Long_Float|Float_IO|'
                        r'Generic_Elementary_Functions|Generic_Vectors)\b|'
                        r'\btype\s+\w+\s+is\s+digits\b', code, re.I),
          'no floating type/library in ' + source.name)

# Check the generated Forge objects, including text and compatibility STL.
# FP register moves are harmless; numeric FP instructions/conversions are banned.
objects = sorted((ROOT / 'obj').glob('forge*.o'))
check(bool(objects), 'compiled Forge objects exist for instruction audit')
if shutil.which('otool'):
    command = ['otool', '-tvV']
elif shutil.which('objdump'):
    command = ['objdump', '-d']
else:
    raise RuntimeError('otool or objdump required for fixed-only instruction audit')
fp_ops = (r'f(?:add|sub|mul|div|sqrt|cmp|cmpe|madd|msub|nmul|nmadd|nmsub|cvt[a-z0-9]*)|'
          r'[su]cvtf|v?(?:add|sub|mul|div|sqrt|comi|ucomi)(?:ss|sd|ps|pd)|'
          r'v?cvt(?:si2s[sd]|s[sd]2si|tts[sd]2si|s[sd]2s[sd])')
for obj in objects:
    listing = subprocess.run(command + [str(obj)], check=True, text=True,
                             capture_output=True).stdout
    check(not re.search(r'\t(?:' + fp_ops + r')\b', listing, re.I),
          'integer-only numeric instructions in ' + obj.name)

with tempfile.TemporaryDirectory(prefix='forge-fixed-') as directory:
    folder = Path(directory)
    original, restored = folder / 'original.obj', folder / 'restored.obj'
    document = folder / 'model.forge'
    tick = decimal(Q)
    run(['box a 2 2 2', f'translate a {tick} 0 0', f'export a {original}',
         f'save {document}', f'load {document}', f'export a {restored}'])
    pts = vertices(original)
    check(all(all((v/Q).denominator == 1 for v in p) for p in pts),
          'every exported coordinate is an exact production grid point')
    check(min(p[0] for p in pts) == -1 + Q and max(p[0] for p in pts) == 1 + Q,
          'one-tick translation survives export exactly')
    check(original.read_bytes() == restored.read_bytes(), 'fixed save/load reproduces OBJ bytes')
    check(document.read_text().startswith('# forge-format 1 numeric fixed48\n'),
          'saved document declares fixed48 profile')
    for tie, expected in ((Q/2, 0), (3*Q/2, 2*Q), (-Q/2, 0), (-3*Q/2, -2*Q)):
        run(['box a 2 2 2', f'translate a {decimal(tie)} 0 0', f'export a {restored}'])
        check(min(p[0] for p in vertices(restored)) == -1 + expected,
              'end-to-end ties-to-even input: ' + decimal(tie))
    for profile in ('floating', 'fixed', 'unknown'):
        document.write_text(f'# forge-format 1 numeric {profile}\nbox b 2 2 2\n')
        reply = run(['box a 2 2 2', f'load {document}', 'info a'], errors=1)
        check('a profile fixed48' in reply, 'incompatible profile preserves fixed model')
    for degrees in ('31', '-31', '135', '359.5', '-720.5'):
        run(['box a 2 2 2', f'rotate a z {degrees}', f'export a {restored}'])
        sine, cosine = reference_trig(F(degrees))
        expected = [(x*cosine-y*sine, x*sine+y*cosine, z)
                    for x, y, z in product((-1, 1), repeat=3)]
        check(all(any(max(abs(a-b) for a, b in zip(point, ref)) < F(1, 10**11)
                      for ref in expected) for point in vertices(restored)),
              'fixed rotation matches rational series reference: ' + degrees)
    for segments in (24, 64, 128, 256):
        # Whole Boolean evaluation, including validation, not just tessellation.
        lines = (ROOT / 'examples/bracket.forge').read_text().splitlines()
        lines = [f'cylinder hole 4 10 {segments}' if line.startswith('cylinder hole ')
                 else line for line in lines if not line.startswith('#')]
        reply = run(lines + ['evaluate cut', 'info cut'])
        check('profile fixed48' in reply and 'solid yes' in reply,
              f'fixed bracket Boolean qualification at {segments} segments')
print(f'{checks} fixed-point acceptance checks passed')
