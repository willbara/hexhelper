#!/usr/bin/env bash
# One-time setup from your copy of Hex Empire (hex_empire.exe, the 2009 Flash projector).
#   scripts/setup.sh /path/to/hex_empire.exe [--with-node]
#
# - splits the projector into the Flash Player stub and the game SWF        -> game/
# - downloads JPEXS FFDec (Flash decompiler/compiler, GPL)                  -> tools/ffdec/
# - decompiles the game's ActionScript (needed by build.sh and the tests)   -> game/src/
# - with --with-node: downloads a Node.js LTS for the tests if none is found -> tools/node/
# game/ and tools/ are in .gitignore, so nothing from the game gets committed.
# Requires: python3, java (11+), curl, unzip.
set -euo pipefail
cd "$(dirname "$0")/.."
EXE=${1:?usage: scripts/setup.sh /path/to/hex_empire.exe [--with-node]}
FFDEC_VERSION=26.3.0

for cmd in python3 java curl unzip; do
  command -v "$cmd" >/dev/null || { echo "missing: $cmd"; exit 1; }
done

mkdir -p game tools
python3 scripts/projector.py split "$EXE" game/projector_stub.exe game/original.swf

if [ ! -f tools/ffdec/ffdec.jar ]; then
  echo "Downloading FFDec $FFDEC_VERSION..."
  curl -sL -o tools/ffdec.zip "https://github.com/jindrapetrik/jpexs-decompiler/releases/download/version$FFDEC_VERSION/ffdec_$FFDEC_VERSION.zip"
  mkdir -p tools/ffdec && unzip -q -o tools/ffdec.zip -d tools/ffdec && rm tools/ffdec.zip
fi

echo "Decompiling game scripts..."
rm -rf game/src
java -jar tools/ffdec/ffdec.jar -export script game/src game/original.swf >/dev/null
test -f game/src/scripts/frame_11/DoAction.as || { echo "decompile failed: frame_11 script not found"; exit 1; }

if [ "${2:-}" = "--with-node" ] && ! command -v node >/dev/null && [ ! -x tools/node/bin/node ]; then
  echo "Downloading Node.js LTS..."
  V=$(curl -s https://nodejs.org/dist/index.json | python3 -c "import json,sys;print([r['version'] for r in json.load(sys.stdin) if r['lts']][0])")
  curl -sL -o tools/node.tar.xz "https://nodejs.org/dist/$V/node-$V-linux-x64.tar.xz"
  tar xf tools/node.tar.xz -C tools && rm tools/node.tar.xz && mv "tools/node-$V-linux-x64" tools/node
fi

echo "Setup done. Next: scripts/build.sh"
