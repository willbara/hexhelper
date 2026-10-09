#!/usr/bin/env bash
# Builds game/hex_empire_hexhelper.exe: your copy of the game with Hex Helper added.
# Run scripts/setup.sh first. Your original exe is never modified.
#
# The game's main script (frame 11) defines all the rules and ends with stop();  the advisor
# (advisor/advisor.as) goes in right before that stop(), then FFDec recompiles that one script.
set -euo pipefail
cd "$(dirname "$0")/.."
test -f game/src/scripts/frame_11/DoAction.as || { echo "run scripts/setup.sh first"; exit 1; }

rm -rf game/mods && mkdir -p game/mods/scripts/frame_11
python3 - <<'PY'
src = open("game/src/scripts/frame_11/DoAction.as", encoding="utf-8").read().rstrip()
assert src.endswith("stop();"), "unexpected end of frame_11 script"
adv = open("advisor/advisor.as", encoding="utf-8").read()
out = src[: -len("stop();")] + adv.rstrip() + "\nstop();\n"
open("game/mods/scripts/frame_11/DoAction.as", "w", encoding="utf-8").write(out)
PY

echo "Compiling..."
java -jar tools/ffdec/ffdec.jar -importScript game/original.swf game/hexhelper.swf game/mods >/dev/null
python3 scripts/projector.py join game/projector_stub.exe game/hexhelper.swf game/hex_empire_hexhelper.exe
echo "Done. Run it with: wine game/hex_empire_hexhelper.exe   (or double-click on Windows)"
