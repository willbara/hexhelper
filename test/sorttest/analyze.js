// Regenerates the experiment's 400 inputs (used by search.js). Run on its own, it compares Flash's results
// with a stable sort.
const fs = require("fs");
const res = fs.readFileSync(__dirname + "/flash_sort_result.txt", "utf8").split(";").map((t) => t.split(",").map(Number));
let seed = 12345;
const R = (n) => { seed = (seed * 16807) % 2147483647; return Math.floor((seed / 2147483647) * n); };
const trials = [];
for (let t = 0; t < 400; t++) {
  const n = 2 + R(30), K = 1 + R(4), arr = [];
  for (let i = 0; i < n; i++) arr.push({ k: R(K), id: i });
  trials.push(arr);
}
const cmp = (a, b) => (a.k > b.k ? -1 : a.k < b.k ? 1 : 0);
module.exports = { res, trials, cmp };
if (require.main === module) {
  let stable = 0, sizeOk = 0;
  trials.forEach((arr, t) => {
    if (res[t].length == arr.length) sizeOk++;
    const js = arr.slice().sort(cmp).map((o) => o.id).join(",");
    if (js == res[t].join(",")) stable++;
  });
  console.log(`inputs regenerated correctly: ${sizeOk}/400   identical to a stable sort: ${stable}/400`);
  for (let t = 0; t < 400; t++) {
    const js = trials[t].slice().sort(cmp).map((o) => o.id).join(",");
    if (js != res[t].join(",")) { console.log("example n=" + trials[t].length, "keys", trials[t].map((o) => o.k).join(""), "\n flash", res[t].join(","), "\n js   ", js); break; }
  }
}
