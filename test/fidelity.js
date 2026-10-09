// Checks that the advisor's model reproduces the game's real rules exactly.
// Plays random and aggressive moves on real maps with the game's own functions, applies the same moves
// to the model, and compares owners / armies / troops / morale after every move and every end of turn.
//   node fidelity.js [seed] [maps]
const { createSandbox, makeBoard, clearDead, endTurn } = require("./lib");
const seed = +(process.argv[2] || 1), maps = +(process.argv[3] || 10);
const ctx = createSandbox({ seed });

function compare(B, st, what) {
  const real = ctx.hwaRootState(B);
  for (let i = 0; i < ctx.hwa.S.n; i++) {
    for (const k of ["ow", "ap", "ac", "am"]) {
      if (real[k][i] !== st[k][i] && !(k == "ow" && ctx.hwa.S.typ[i] == 0)) {
        const f = ctx.hwa.S.fld[i];
        return `${what}: ${k} differs at ${f.fx},${f.fy} real=${real[k][i]} model=${st[k][i]}`;
      }
    }
  }
  return null;
}

let moves = 0, battles = 0, ends = 0, errors = 0;
for (let m = 0; m < maps; m++) {
  const B = makeBoard(ctx, 0);
  B.move_points = 5;
  ctx.hwaBuildStatic(B);
  for (let turn = 0; turn < 60 && !B.stopped; turn++) {
    for (let p = 0; p < 4 && !B.stopped; p++) {
      if (!B.hw_parties_armies[p].length) continue;
      B.turn_party = p;
      const mp = Math.min(5, B.hw_parties_armies[p].length);
      for (let k = 0; k < mp; k++) {
        const movable = ctx.getMovableArmies(p, B);
        if (!movable.length) break;
        let a, t;
        if (ctx.rnd() < 0.5) {
          a = movable[Math.floor(ctx.rnd() * movable.length)];
          const opts = ctx.getPossibleMoves(a.field, true, false);
          if (!opts.length) continue;
          t = opts[Math.floor(ctx.rnd() * opts.length)];
        } else {
          let best = -1;
          for (const c of movable) for (const f of ctx.getPossibleMoves(c.field, true, false)) {
            const v = (f.army && f.army.party != p ? 50 + c.count - f.army.count : 0) + (f.estate && f.party != p ? 30 : 0) + ctx.rnd() * 10;
            if (v > best) { best = v; a = c; t = f; }
          }
          if (!a) continue;
        }
        if (t.army && t.army.party != p) battles++;
        const st = ctx.hwaRootState(B);
        ctx.hwaApply(st, a.field.hwa_i, t.hwa_i, null);
        ctx.moveArmy(a, t);
        clearDead(B); ctx.updateBoard(B);
        moves++;
        const e = compare(B, st, `map ${m} turn ${turn} party ${p} move ${k}`);
        if (e) { errors++; if (errors <= 8) console.log(e); }
        if (B.stopped) break;
      }
      const st = ctx.hwaRootState(B);
      ctx.hwaEndTurn(st, p);
      endTurn(ctx, B, p);
      ends++;
      const e = compare(B, st, `map ${m} turn ${turn} party ${p} END`);
      if (e) { errors++; if (errors <= 8) console.log(e); }
    }
  }
}
console.log(`maps=${maps} moves=${moves} battles=${battles} turnEnds=${ends} mismatches=${errors}`);
process.exit(errors ? 1 : 0);
