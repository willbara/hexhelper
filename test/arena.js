// Full games against the game's real AI. Your seat (nation 0) is played by Hex Helper ("adv") or by the
// game's own AI ("ai"); nations 1-3 are always the game's AI at the given difficulty (0, 5 or 10 = hard).
//   node arena.js [adv|ai] [games] [difficulty] [seed]
// Environment:
//   HWA_AGGR=1           aggressive mode
//   HWA_OVERRIDE='{...}' override advisor settings (HWA_W), e.g. '{"rerank":8}'
//   CONF=1               also report step confidence and live enemy-prediction accuracy
//   FIDELITY=1           (mode ai) report how often the advisor's copy of the AI predicts a whole AI turn exactly
//   ADV_FILE=path        test a decompiled DoAction.as from a built SWF instead of advisor/advisor.as
const { createSandbox, makeBoard, clearDead, endTurn } = require("./lib");
const mode = process.argv[2] || "adv";
const games = +(process.argv[3] || 10);
const difficulty = +(process.argv[4] || 10);
const seed = +(process.argv[5] || 7);
const ctx = createSandbox({ seed, difficulty });
ctx.hwa.aggr = !!process.env.HWA_AGGR;
if (process.env.HWA_OVERRIDE) Object.assign(ctx.HWA_W, JSON.parse(process.env.HWA_OVERRIDE));

const diag = [];
let wins = 0, losses = 0, draws = 0, winTurns = 0, firstKills = [];
let searches = 0, searchMs = 0, maxSearch = 0, evals = 0, speeches = 0, pacts = 0;
let confSum = 0, confN = 0, fidTurns = 0, fidSame = 0;
const origEval = ctx.hwaEval;
ctx.hwaEval = function (a, b) { evals++; return origEval(a, b); };

for (let g = 0; g < games; g++) {
  const B = makeBoard(ctx, 0);
  ctx.hwa.target = -1; ctx.hwa.predNext = null;
  let result = "draw", firstKill = 0; const killTurns = [];
  for (let turn = 0; turn < 120 && result == "draw"; turn++) {
    B.turns = turn + 1;
    for (let p = 0; p < 4 && result == "draw"; p++) {
      if (!B.hw_parties_armies[p].length) continue;
      B.turn_party = p;
      B.move_points = Math.min(5, B.hw_parties_armies[p].length);
      if (p == 0 && mode == "adv") {
        if (process.env.CONF && ctx.hwa.predNext) ctx.hwaCheckPrediction(B);
        const t0 = Date.now();
        ctx.hwaStartSearch(B);
        while (!ctx.hwa.job.done) ctx.hwaStep();
        ctx.hwaFinish();
        const ms = Date.now() - t0; searchMs += ms; searches++; if (ms > maxSearch) maxSearch = ms;
        if (process.env.CONF) for (const d of ctx.hwa.plan) { confSum += d.conf; confN++; }
        for (const d of ctx.hwa.plan) {
          if (d.code < 0) {
            if (d.code == -1) { ctx.addMoraleForAll(50, 0, B); B.hw_parties_speech_given[0] = true; speeches++; }
            else if (ctx.signPact(-d.code - 10, B)) { B.hw_pact_signed = true; pacts++; }
            continue;
          }
          const sf = ctx.hwa.S.fld[d.s], tf = ctx.hwa.S.fld[d.t];
          if (!sf.army || sf.army.party != 0) { console.log("plan step invalid"); break; }
          ctx.moveArmy(sf.army, tf);
          clearDead(B); ctx.updateBoard(B);
          if (B.stopped) break;
        }
      } else {
        let pst = null, XX = null;
        if (process.env.FIDELITY) {
          ctx.hwaBuildStatic(B); ctx.hwa.S.human = 0;
          pst = ctx.hwaRootState(B);
          const X = ctx.hwaAIContext(B);
          XX = { human: 0, diff: difficulty, turns: B.turns, wfs: new Array(ctx.hwa.S.n), wfsF: X.wfsF.slice(), wfsC: X.wfsC.slice(), peace: B.hw_peace };
          let di = 0; for (let z = 0; z < 4; z++) if (pst.ow[ctx.hwa.S.capF[z]] == z) di++;
          XX.duel = di < 3; XX.wfsField = XX.wfsF[p]; XX.wfsCount = XX.wfsC[p];
          let pmp = B.move_points;
          while (pmp > 0) { let mv = 0; for (let i = 0; i < ctx.hwa.S.n; i++) if (pst.ap[i] == p && !pst.mv[i]) mv++; if (pmp > mv) pmp = mv; if (pmp <= 0) break; ctx.hwaAIMove(pst, p, XX); pmp--; }
        }
        for (let guard = 0; guard < 10; guard++) {
          const movable = ctx.getMovableArmies(p, B).length;
          if (B.move_points > movable) B.move_points = movable;
          if (B.move_points <= 0) break;
          ctx.makeMove(p, B, false);
          clearDead(B); ctx.updateBoard(B);
          if (B.stopped) break;
        }
        if (pst && !B.stopped) {
          const real = ctx.hwaRootState(B);
          let diff = 0; for (let i = 0; i < ctx.hwa.S.n; i++) if (real.ap[i] != pst.ap[i] || real.ac[i] != pst.ac[i]) diff++;
          fidTurns++; if (!diff) fidSame++;
        }
      }
      if (B.stopped) { result = B.win ? "win" : "loss"; break; }
      endTurn(ctx, B, p);
      if (process.env.CONF && p == 0 && mode == "adv") { ctx.hwa.S = null; ctx.hwaSnapshotPrediction(B); }
      if (B.hw_parties_capitals[0].party != 0) result = "loss";
      else if ([1, 2, 3].every((q) => !B.hw_parties_armies[q].length && B.hw_parties_capitals[q].party != q)) result = "win";
    }
    if (!firstKill && [1, 2, 3].some((q) => B.hw_parties_capitals[q].party != q)) { firstKill = B.turns; firstKills.push(firstKill); }
    if (process.env.DIAG) {
      const dead = [1, 2, 3].filter((q) => B.hw_parties_capitals[q].party != q).length;
      while (killTurns.length < dead) killTurns.push(B.turns);
    }
  }
  if (result == "win") { wins++; winTurns += B.turns; } else if (result == "loss") losses++; else draws++;
  if (process.env.DIAG) {
    const cap = B.hw_parties_capitals[0];
    const pw = B.hw_parties_total_power.map((x) => x | 0).join("/");
    diag.push({ result, turn: B.turns, kills: killTurns.slice(), by: result == "loss" ? cap.party : -1, pw });
  }
  process.stdout.write(result[0]);
}
if (process.env.DIAG) {
  for (const d of diag) console.log(`${d.result.padEnd(4)} turn ${String(d.turn).padStart(3)}  eliminations at ${d.kills.join(",") || "-"}${d.by >= 0 ? "  capital taken by " + d.by : ""}  power ${d.pw}`);
  const k = (i) => { const v = diag.filter((d) => d.kills.length > i).map((d) => d.kills[i]); return v.length ? (v.reduce((a, b) => a + b, 0) / v.length).toFixed(1) : "-"; };
  console.log(`avg elimination turns: 1st ${k(0)}  2nd ${k(1)}  3rd ${k(2)}`);
  const lt = diag.filter((d) => d.result == "loss").map((d) => d.turn);
  console.log(`loss turns: ${lt.join(",")}`);
}
const avg = (a) => (a.length ? (a.reduce((x, y) => x + y, 0) / a.length).toFixed(1) : "-");
console.log("");
if (process.env.FIDELITY) console.log(`AI turns predicted exactly: ${fidSame}/${fidTurns}`);
if (process.env.CONF) console.log(`avg step confidence ${(confSum / confN).toFixed(1)}%  enemy prediction accuracy (rolling) ${(ctx.hwa.predAcc * 100).toFixed(1)}%`);
if (mode == "adv") console.log(`speeches=${speeches} pacts=${pacts}`);
console.log(`avgWinTurn=${wins ? (winTurns / wins).toFixed(1) : "-"} firstKill=${avg(firstKills)}`);
console.log(`mode=${mode}${ctx.hwa.aggr ? "/aggressive" : ""} difficulty=${difficulty} games=${games}  wins=${wins} losses=${losses} draws=${draws}`);
if (searches) console.log(`searches=${searches} avg=${(searchMs / searches).toFixed(1)}ms max=${maxSearch}ms evals/search=${(evals / searches).toFixed(0)}`);
