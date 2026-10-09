# Tests

Offline tests for Hex Helper (`../advisor/advisor.as`). They load the game's **real rules** (frame 11 of
your decompiled copy in `../game/src`, created by `scripts/setup.sh`) and the advisor into one Node.js
sandbox, generate maps with the game's own map generator, and play full games against the game's own AI.
Nothing here modifies any game file.

Needs Node.js 18+ (`node` on your PATH, or `scripts/setup.sh <exe> --with-node` downloads one into
`tools/node`).

| file | what it does |
|---|---|
| `lib.js` | loads rules + advisor, builds boards (graphics stubbed), installs Flash's sort, shared helpers |
| `fidelity.js` | checks the advisor's model reproduces the real rules exactly (every move and end of turn) |
| `arena.js` | full games: your seat played by Hex Helper (`adv`) or the game's AI (`ai`) vs 3 AIs |
| `sweep.sh` | runs several advisor configurations on the same maps (4 at a time, low priority; `JOBS=n` to change) |
| `sorttest/` | the experiment that measured how Flash's `Array.sort` orders ties (see its README) |

## Commands (from this folder)

```sh
node fidelity.js 1 10                       # rules check: expect "mismatches=0"
node arena.js adv 50 10 777                 # 50 hard games, Hex Helper in normal mode
HWA_AGGR=1 node arena.js adv 50 10 777      # same, aggressive mode
node arena.js ai 50 10 777                  # baseline: the game's own AI in your seat
FIDELITY=1 node arena.js ai 20 10 11        # share of AI turns the advisor's copy of the AI predicts exactly
CONF=1 node arena.js adv 20 10 1            # also report step confidence and live prediction accuracy
DIAG=1 HWA_AGGR=1 node arena.js adv 50 10 1 # per-game elimination turns and how losses happened
HWA_OVERRIDE='{"rerank":8}' node arena.js adv 50 10 777   # try other settings (HWA_W in advisor.as)

# compare settings on the same maps (N = normal, A = aggressive):
./sweep.sh 200 10 777 <<'EOF'
N {}
A {}
A {"aggThreat":0.5}
EOF
```

Arguments are `[adv|ai] [games] [difficulty] [seed]`; difficulty is 0, 5 or 10 (hard). The same seed gives the
same maps, so compare settings with one seed and confirm a winner on a second seed before adopting it -
differences of under ~10 games in 200 are noise.

To test a *built* game instead of the source, decompile it and point `ADV_FILE` at the script:

```sh
java -jar ../tools/ffdec/ffdec.jar -export script /tmp/hexcheck ../game/hexhelper.swf
ADV_FILE=/tmp/hexcheck/scripts/frame_11/DoAction.as node arena.js adv 20 10 1
```

## Notes
- Every game runs on one core. `sweep.sh` runs 4 at a time at the lowest priority by default, and a
  200-game run takes roughly 10-15 minutes per configuration.
- Search times reported here use Node's JIT; Flash's ActionScript 2 engine is much slower. `node --jitless`
  gives a closer idea. In the game the advisor adapts its search size to how long it takes.
- ActionScript 2 returns `undefined` when reading a property of something missing, and the game relies on
  that; `lib.js` rewrites the rules to use optional chaining so they run the same way in JavaScript.
- The game's AI occasionally "moves" an army that has nowhere to go. That's a bug in the game, and in
  Flash the army drops off the board. Both the tests and the advisor's copy of the AI reproduce it.
