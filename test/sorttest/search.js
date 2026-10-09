const { res, trials, cmp } = require("./analyze");
let ops = 0;
const guard = () => { if (++ops > 200000) throw new Error("loop"); };
const sw = (a, i, j) => { guard(); const t = a[i]; a[i] = a[j]; a[j] = t; };
function pivIdx(lo, hi, p) { return p == 0 ? (lo + hi) >> 1 : p == 1 ? (lo + hi + 1) >> 1 : p == 2 ? lo : hi; }
// family A: pivot swapped to lo, pointers scan against a[lo]
function famA(a, c0, o) {
  const c = (x, y) => { guard(); return c0(x, y); };
  const stk = [[0, a.length - 1]];
  while (stk.length) {
    const [lo, hi] = stk.pop();
    if (lo >= hi) continue;
    if (o.small && hi - lo + 1 <= o.small) { for (let i = lo + 1; i <= hi; i++) for (let j = i; j > lo && c(a[j - 1], a[j]) > 0; j--) sw(a, j - 1, j); continue; }
    sw(a, pivIdx(lo, hi, o.p), lo);
    let i = lo + 1, j = hi;
    for (;;) {
      while (i <= hi && (o.lc ? c(a[i], a[lo]) <= 0 : c(a[i], a[lo]) < 0)) i++;
      while (j > lo && (o.rc ? c(a[j], a[lo]) >= 0 : c(a[j], a[lo]) > 0)) j--;
      if (o.brk ? i > j : i >= j) break;
      sw(a, i, j);
      if (o.inc) { i++; j--; }
    }
    sw(a, lo, j);
    stk.push([lo, j - 1]); stk.push([j + 1, hi]);
  }
  return a;
}
// family B: pivot value, classic Hoare with i/j crossing
function famB(a, c0, o) {
  const c = (x, y) => { guard(); return c0(x, y); };
  const stk = [[0, a.length - 1]];
  while (stk.length) {
    const [lo, hi] = stk.pop();
    if (lo >= hi) continue;
    if (o.small && hi - lo + 1 <= o.small) { for (let i = lo + 1; i <= hi; i++) for (let j = i; j > lo && c(a[j - 1], a[j]) > 0; j--) sw(a, j - 1, j); continue; }
    const pv = a[pivIdx(lo, hi, o.p)];
    let i = lo, j = hi;
    if (o.v == 0) {
      while (i <= j) {
        while (c(a[i], pv) < 0) i++;
        while (c(a[j], pv) > 0) j--;
        if (i <= j) { sw(a, i, j); i++; j--; }
      }
      stk.push([lo, j]); stk.push([i, hi]);
    } else {
      i = lo - 1; j = hi + 1;
      for (;;) {
        do i++; while (c(a[i], pv) < 0);
        do j--; while (c(a[j], pv) > 0);
        if (i >= j) break;
        sw(a, i, j);
      }
      stk.push([lo, j]); stk.push([j + 1, hi]);
    }
  }
  return a;
}
function score(fn) {
  let ok = 0;
  trials.forEach((arr, t) => { ops = 0; try { if (fn(arr.slice()).map((x) => x.id).join(",") == res[t].join(",")) ok++; } catch (e) {} });
  return ok;
}
const out = [];
for (const p of [0, 1, 2, 3]) for (const small of [0, 3, 4, 6, 8]) {
  for (const lc of [0, 1]) for (const rc of [0, 1]) for (const brk of [0, 1]) for (const inc of [0, 1])
    out.push([score((a) => famA(a, cmp, { p, small, lc, rc, brk, inc })), JSON.stringify({ fam: "A", p, small, lc, rc, brk, inc })]);
  for (const v of [0, 1]) out.push([score((a) => famB(a, cmp, { p, small, v })), JSON.stringify({ fam: "B", p, small, v })]);
}
out.sort((x, y) => y[0] - x[0]).slice(0, 8).forEach(([s, n]) => console.log(s + "/400 " + n));
