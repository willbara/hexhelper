// Shared test setup: loads the game's real rules (frame_11 of your decompiled copy, game/src) and the Hex Helper advisor
// into one sandbox, and builds boards with the game's own map generator (graphics stubbed out).
//
// ActionScript 2 quietly returns `undefined` when code reads a property of something missing; the game
// relies on that (e.g. edge hexes have missing neighbours). JavaScript throws instead, so the rules are
// rewritten to use optional chaining (?.) for every read before they are loaded.
const fs = require("fs");
const vm = require("vm");
const path = require("path");
const ROOT = path.resolve(__dirname, "..");

function lenient(expr) {
  return expr.replace(/(?<=[\w\)\]])\.(?=[A-Za-z_])/g, "?.").replace(/Math\?\./g, "Math.");
}
function splitAssign(line) {
  let depth = 0;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if ("([{".includes(ch)) depth++;
    else if (")]}".includes(ch)) depth--;
    else if (ch == "=" && depth == 0) {
      const prev = line[i - 1] || "", next = line[i + 1] || "";
      if (next == "=" || "=!<>".includes(prev)) continue;
      const start = "+-*/".includes(prev) ? i - 1 : i;
      return [line.slice(0, start), line.slice(start, i + 1), line.slice(i + 1)];
    }
  }
  return null;
}
function lenientRules(src) {
  return src.split("\n").map((line) => {
    const t = line.trim();
    if (line.includes("new ")) return line.replace(/(neighbours\[[^\]]+\])\./g, "$1?.");
    if (t.startsWith("_global.") && line.includes("function")) return line;
    if (/^(if|while|return|else|\}|\{|function)/.test(t)) return lenient(line);
    const sp = splitAssign(line);
    if (sp) return sp[0] + sp[1] + lenient(sp[2]);
    if (/^\s*(\+\+|--)/.test(line) || /(\+\+|--);\s*$/.test(line)) return line;
    return lenient(line);
  }).join("\n");
}

// advisor source: advisor/advisor.as by default, or a decompiled DoAction.as from a built SWF (ADV_FILE)
function advisorSource() {
  const file = process.env.ADV_FILE || path.join(ROOT, "advisor/advisor.as");
  const src = fs.readFileSync(file, "utf8");
  const start = src.indexOf("_global.HWA_W =");
  return src.slice(start, src.indexOf("if(!_global.hwa)"));
}

const FLASH_SORT = `
Array.prototype.sort = function (c) {
  if (typeof c !== "function") c = function (x, y) { x = String(x); y = String(y); return x < y ? -1 : x > y ? 1 : 0; };
  var a = this, stk = [[0, a.length - 1]];
  while (stk.length) {
    var r = stk.pop(), lo = r[0], hi = r[1];
    if (lo >= hi) continue;
    var i = lo + 1, j = hi, t;
    for (;;) {
      while (i <= hi && c(a[i], a[lo]) < 0) i++;
      while (j > lo && c(a[j], a[lo]) >= 0) j--;
      if (i >= j) break;
      t = a[i]; a[i] = a[j]; a[j] = t;
    }
    t = a[lo]; a[lo] = a[j]; a[j] = t;
    stk.push([lo, j - 1]); stk.push([j + 1, hi]);
  }
  return a;
};`;

function createSandbox(opts = {}) {
  let seed = opts.seed || 1;
  const rnd = () => { seed = (seed * 16807) % 2147483647; return seed / 2147483647; };
  const ctx = { console };
  vm.createContext(ctx);
  // the sandbox has its own built-ins; give its Array the same sort Flash's ActionScript 2 uses
  // (an unstable quicksort with the first element as pivot, measured in the real player: see test/sorttest)
  vm.runInContext(FLASH_SORT, ctx);
  ctx.Math = Object.create(vm.runInContext("Math", ctx)); ctx.Math.random = rnd;
  ctx._global = ctx;
  ctx._root = { difficulty: opts.difficulty ?? 10 };
  ctx.pn = 0; // a stray global the map generator increments
  ctx.getTimer = () => 0; // the advisor's own clock; time caps never trigger in tests
  const rulesFile = path.join(ROOT, "game/src/scripts/frame_11/DoAction.as");
  if (!fs.existsSync(rulesFile)) throw new Error("game rules not found; run scripts/setup.sh with your copy of hex_empire.exe first");
  const rules = fs.readFileSync(rulesFile, "utf8");
  vm.runInContext(lenientRules(rules.slice(0, rules.indexOf("var _mochiads_game_id"))), ctx);
  vm.runInContext(advisorSource(), ctx);
  // visuals / sounds -> no-ops
  ctx.playSound = () => {}; ctx.putBelow = () => {}; ctx.updateField = () => {};
  ctx.removeMovieClip = (a) => { a._removed = true; };
  // the game's AI occasionally "moves" an army that has nowhere to go (a bug in the game). In Flash the army
  // loses its hex and drops out of the game; JavaScript would throw, so this wrapper reproduces that outcome
  const mv = ctx.moveArmy;
  ctx.moveArmy = function (a, f) { if (!f) { if (a.field && a.field.army == a) a.field.army = null; a.field = undefined; a.moved = true; return false; } return mv(a, f); };
  ctx.flash = { display: { BitmapData: function () { this.dispose = () => {}; } }, filters: { GlowFilter: function () {} }, geom: { Point: function () {}, Matrix: function () {} } };
  ctx.flash.display.BitmapData.loadBitmap = () => ({ dispose() {}, width: 10, height: 10 });
  ctx.flipBitmap = (b) => b; ctx.rotateBitmap = (b) => b; ctx.pasteBitmap = () => {};
  ctx.hwa = { show: true, plan: [], danger: [], aggr: false, target: -1, level: 3, predN: 0, predAcc: 0 };
  ctx.HWA_W.autoSpeed = 0;
  ctx.rnd = rnd;
  return ctx;
}

function mkClip(parent, name) {
  const o = { _parent: parent, _name: name, _x: 0, _y: 0, depth: 0, town_sign: {}, port: {}, town: {} };
  o.getNextHighestDepth = function () { return ++this.depth; };
  o.attachMovie = function (n, inst) { const c = mkClip(this, inst); c.sea = mkClip(c, "sea"); this[inst] = c; return c; };
  o.createEmptyMovieClip = function (inst) { const c = mkClip(this, inst); this[inst] = c; return c; };
  o.attachBitmap = function () {};
  o.getDepth = function () { return 0; };
  o.swapDepths = function () {};
  o.removeMovieClip = function () {};
  return o;
}

// a new board exactly as the game sets one up (frame 1 + generateMap + frame 3 spawns + AI helper tables)
function makeBoard(ctx, human = 0) {
  const B = mkClip({ gotoAndPlay() {} }, "board");
  Object.assign(B, {
    hw_init: true, hw_xmax: 20, hw_ymax: 11, hw_fw: 50, hw_fh: 40, hw_land: 0, hw_top_field_depth: 0, hw_lands: [], hw_towns: [],
    hw_status_names: ["Province", "Kingdom", "Empire", "Empire", "Empire"], hw_parties_count: 4,
    hw_parties_names: ["Redosia", "Violetnam", "Bluegaria", "Greenland"], hw_parties_colors: [0xff0000, 0xff00ff, 0x00bbff, 0x00ff00],
    hw_parties_capitals: [], hw_parties_provinces_cp: [[], [], [], []], hw_parties_towns: [[], [], [], []], hw_parties_ports: [[], [], [], []],
    hw_parties_lands: [[], [], [], []], hw_parties_morale: [10, 10, 10, 10], hw_parties_armies: [[], [], [], []], hw_parties_status: [1, 1, 1, 1],
    hw_parties_total_count: [0, 0, 0, 0], hw_parties_total_power: [0, 0, 0, 0], hw_parties_control: ["computer", "computer", "computer", "computer"],
    hw_parties_wait_for_support_field: [null, null, null, null], hw_parties_wait_for_support_count: [0, 0, 0, 0],
    hw_parties_speech_given: [false, false, false, false], hw_pact_signed: false, hw_pact_just_broken: -1, hw_peace: -1,
    hw_lAID: 0, hw_aTL: 0, lh_area: 0, news: "", subject: null, turns: 0,
  });
  B.stop = function () { this.stopped = true; };
  ctx.rnd_seed = Math.floor(ctx.rnd() * 10000);
  ctx.generateMap(B);
  ctx.updateBoard(B);
  for (let x = 0; x < 20; x++) for (let y = 0; y < 11; y++) B["f" + x + "x" + y].profitability = [];
  for (let p = 0; p < 4; p++) for (let y = 0; y < 11; y++) ctx.calcAIHelpers(p, y, B);
  B.hw_init = false;
  B.human = human;
  B.hw_parties_control[human] = "human";
  for (let p = 0; p < 4; p++) { ctx.unitsSpawn(p, B); ctx.updateBoard(B); }
  return B;
}

// armies that lost a fight stay on their hex for ~36 frames while exploding; tests remove them right away
function clearDead(B) {
  for (let x = 0; x < 20; x++) for (let y = 0; y < 11; y++) {
    const f = B["f" + x + "x" + y];
    if (f.army && f.army.remove_time >= 0) f.army = null;
  }
}

function endTurn(ctx, B, p) {
  ctx.cleanupTurn(B); ctx.updateBoard(B); ctx.unitsSpawn(p, B); ctx.updateBoard(B); clearDead(B);
}

module.exports = { createSandbox, makeBoard, clearDead, endTurn, ROOT };
