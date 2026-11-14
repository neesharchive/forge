
#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/../cli"

output=$(printf '%s\n' \
  'box base 4 2 3' \
  'summary' \
  'translate base 2 0 0' \
  'summary' \
  'undo' \
  'summary' | alr run)

check() {
  if grep -Fq -- "$1" <<< "$output"; then
    echo "PASS  $2"
  else
    echo "FAIL  $2"
    exit 1
  fi
}

check "Solids: 1" "solid count"
check "Vertices:" "vertex information"
check "Triangles:" "triangle information"
check "24.0000000000" "box volume"
check "Valid Solid: Yes" "mesh validity"
check "History: 2" "translation recorded"
check "History: 1" "undo updates history"
check "translate base 2 0 0" "translation displayed"

echo "CLI summary tests passed"


# Test STL export through the CLI
stl_file=$(mktemp "${TMPDIR:-/tmp}/forge_export_XXXXXX.stl")
trap 'rm -f "$stl_file"' EXIT

export_output=$(printf '%s\n' \
  'box export_test 4 2 3' \
  "export export_test $stl_file" \
  'summary' | alr run)

if grep -Fq "ok wrote 684 bytes" <<< "$export_output" &&
   [ -f "$stl_file" ] &&
   [ "$(wc -c < "$stl_file" | tr -d '[:space:]')" = "684" ] &&
   [ "$(od -An -tu4 -j80 -N4 "$stl_file" | tr -d '[:space:]')" = "12" ] &&
   grep -Fq "History: 1" <<< "$export_output"; then
  echo "PASS  STL export creates a 684-byte file without changing history"
else
  echo "FAIL  STL export"
  exit 1
fi


# Test STL export after translation
moved_file=$(mktemp "${TMPDIR:-/tmp}/forge_moved_XXXXXX.stl")

moved_output=$(printf '%s\n' \
  'box moved_box 4 2 3' \
  'translate moved_box 5 0 0' \
  "export moved_box $moved_file" | alr run)

if python3 - "$moved_file" <<'PY'
import struct
import sys

with open(sys.argv[1], "rb") as f:
    data = f.read()

count = struct.unpack_from("<I", data, 80)[0]
vertices = []

for i in range(count):
    offset = 84 + i * 50
    for j in range(3):
        vertices.append(struct.unpack_from("<3f", data, offset + 12 + j * 12))

assert count == 12
assert min(v[0] for v in vertices) == 3.0
assert max(v[0] for v in vertices) == 7.0
PY
then
  echo "PASS  STL export preserves translated geometry"
else
  echo "FAIL  STL export after translation"
  rm -f "$moved_file"
  exit 1
fi

rm -f "$moved_file"

