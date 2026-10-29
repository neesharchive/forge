#!/usr/bin/env sh
# Reproducible local/CI gate. ALR can select a non-PATH Alire executable.
set -eu
cd "$(dirname "$0")/.."
ALR_EXECUTABLE="${ALR:-alr}"
# GNAT 16's Darwin linker cannot parse newer SDK library stubs on some Macs.
# Prefer an already-installed compatible SDK without changing global settings.
if [ "$(uname -s)" = Darwin ] && \
   [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk ]; then
  SDKROOT="${FORGE_SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk}"
  export SDKROOT
fi
"$ALR_EXECUTABLE" -n build
(cd tests && "$ALR_EXECUTABLE" -n build && ./bin/tests)
(cd cli && "$ALR_EXECUTABLE" -n build)
python3 tests/integration.py
python3 tests/fixed_point.py
"$ALR_EXECUTABLE" -n exec -- gnatprove -P forge.gpr --mode=flow --checks-as-errors=on
"$ALR_EXECUTABLE" -n exec -- gnatprove -P forge.gpr --mode=prove --level=2 -f \
  --checks-as-errors=on -u forge-fixed.adb forge-grid.adb forge-model.adb forge-numeric.ads forge-history.adb
