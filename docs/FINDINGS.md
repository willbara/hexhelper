# Findings

What we learned building Hex Helper: how Hex Empire works under the hood, how the game's AI decides, and
what made the advisor stronger. The results come from roughly 52,000 simulated games against the game's
own AI, plus ~170,000 rule-check moves and one experiment inside the real Flash Player.

All win rates are for your nation against three AI nations. On Hard (difficulty 10) the AI is biased to
target you and to avoid fighting each other, so it's effectively 1 vs 3.

## Game mechanics (from the decompiled code, verified move-for-move)

**Board.** 20 x 11 hexes, 4 nations, capitals start in the corners. Land, sea, towns and ports; ports are
land hexes next to sea and are the only way onto the water.

**Turns.** Each turn you get `min(5, number of armies)` moves. An army moves 1 hex, or 2 hexes if the hex in
between is empty and has no town or port. From a port it can also move into the sea; at sea it moves
through empty sea hexes and can land anywhere adjacent.

**Combat.** There's no randomness. Power = troops + morale, and morale is capped at the army's troop count.
- The attacker wins if its power is strictly greater; ties go to the defender.
- The winner loses `floor(enemyPower / ownPower * troops)` troops (at least 1 survives); the loser is destroyed.
- The losing side's whole nation loses `floor(loserTroops / 10)` morale on every army.

**Annexing.** Moving onto a land hex claims it plus every adjacent empty land hex without a town or port.
Morale gained (all armies / the moving army): capital 50/30 (an already-conquered capital 30/20),
town 10/10, port 5/5, each land hex 1/0. The previous owner loses 30 / 10 / 5 morale on all armies for a
conquered capital / town / port.

**Elimination.** Taking a nation's own capital eliminates it instantly: all its armies are destroyed and all
its land becomes yours. Capitals that nation had conquered are liberated with fresh 99/99 armies. Taking
any capital while you already hold two conquered capitals (whose nations have no armies left) wins the game.

**Income (end of each of your turns).** With T towns (capitals count), P ports and L land hexes, every town
gets `5 + floor((L + 5P) / T)` troops and each capital you hold gets 5 more. So a town and a port are each
worth about 5 troops per turn and each land hex about 1. Ports add to every town's spawn, and towns are
where the troops appear. Armies are capped at 99 and any overflow is lost.

**Morale upkeep.** Armies that didn't move lose 1 morale at the end of the turn, and every army's morale is
at least `floor(nation's total troops / 50)`.

**Give Speech** (once per game) adds 50 morale to every one of your armies, still capped by troops.
**Sign Pact** (once per game, refused when you're much weaker than someone) makes that nation's AI stop
attacking you while 3 or more nations still hold their capitals. Breaking it by moving onto their land
gives them 30 morale.

## How the game's AI decides

On each AI move, every movable army scores each hex it can reach with `finalProfitability`:
- distance to the nearest enemy capital (precomputed paths; on Hard, +20 toward your capital);
- +1,000,000 for a capital it can take, +20 near capitals, +5 for towns, +3 for ports and hexes near towns;
- on Hard, -250 for attacking non-human armies, which is why all three AIs gang up on you;
- a "wait for support" flag when the area around the target is stronger than its own forces nearby.

It moves the best army to its best hex. If that move is flagged "wait for support", it moves the nearest
other army toward the target instead, for up to 5 turns of waiting. The AI has no randomness except in
how it breaks ties, which goes through Flash's unstable `Array.sort` (measured in
`test/sorttest/README.md`). With that sort reproduced, the advisor's copy predicts 100% of AI turns in tests.

## How Hex Helper got stronger (Hard, % of games won)

| step | normal | notes |
|---|---|---|
| Game's own AI in your seat | 0% | baseline (0/50) |
| Score each move on its own (first version) | - | easily outplayed by the AI |
| Simulator + beam search of whole turns | 23-33% | exact rules model, 5-move plans |
| Wider search | 38-42% | little gain past ~400 positions per turn |
| Replay the enemy turn with a copy of the AI, re-rank the top 16 plans | 52-64% | the biggest single jump |
| Sign Pact + Give Speech as plan steps | +5-6 points | the pact does most of it (+8-9 points in aggressive mode) |
| Tuning: less fear of counter-attacks, enemy losses worth ~2x | 82% | it had been playing too passively |
| Exact AI copy (Flash tie-breaking) | 84% | measured against the faithful opponent |

Aggressive mode goes after the nation that's cheapest to eliminate. It won 64% when introduced, 76-85%
after its first tuning, and 87-92% with pacts, speeches and the exact AI copy. It wins in ~32-34 turns,
against ~37 for normal mode. On Medium both modes win 94-96%.

### What didn't help
- Looking one more turn ahead (a greedy version of your next turn after the enemy replay).
- A "gang-up" threat model (several enemy armies attacking one target in sequence), either for every
  target or only for your capital.
- Moving distant armies toward the next target before the current one falls. It weakens the assault.
- Ignoring armies of nations other than the target: 70% wins against 89%.
- More caution in aggressive mode, or using the speech more freely.
- Fine-tuning aggressive mode past its current settings. All ~35 variants landed within noise.

### Where games are decided (aggressive mode, Hard)
On average the eliminations happen at turns 11, 24 and 33, so the second nation takes longest. The ~10% of
losses are all your capital falling (turns 6-35), usually to an AI that builds up nearby over several turns.

## Method notes
- Every comparison ran on the same maps (same seed), and we confirmed each winner on a second, unseen set of
  maps before adopting it. With 200 games, differences under ~10 games are noise.
- `test/fidelity.js` checks the rules model against the game's real functions after every move and end of
  turn, and expects 0 mismatches.
- The earlier rows were measured against an opponent that broke ties like JavaScript. We re-measured the last
  row and the aggressive figures against the exact Flash behaviour.
