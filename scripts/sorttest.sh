#!/usr/bin/env bash
# Rebuilds the Flash sort experiment from your copy of the game (see test/sorttest/README.md).
# Produces game/sorttest.exe: the game with test/sorttest/sort_experiment.as run at load. Launch it
# once (wine game/sorttest.exe), close it after a few seconds, then run:
#   python3 test/sorttest/read_sol.py > test/sorttest/flash_sort_result.txt
set -euo pipefail
cd "$(dirname "$0")/.."
test -f game/src/scripts/frame_1/DoAction.as || { echo "run scripts/setup.sh first"; exit 1; }
rm -rf game/sortmods && mkdir -p game/sortmods/scripts/frame_1
cat test/sorttest/sort_experiment.as game/src/scripts/frame_1/DoAction.as > game/sortmods/scripts/frame_1/DoAction.as
java -jar tools/ffdec/ffdec.jar -importScript game/original.swf game/sorttest.swf game/sortmods >/dev/null
python3 scripts/projector.py join game/projector_stub.exe game/sorttest.swf game/sorttest.exe
