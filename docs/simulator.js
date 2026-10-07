const NAMES = {
  total_trans_ct: "Transaction count",
  total_trans_amt: "Transaction amount",
  months_inactive_12_mon: "Inactive months",
  avg_utilization_ratio: "Credit utilization",
  total_relationship_count: "Products held",
  contacts_count_12_mon: "Contacts (12 mo)",
};

fetch("data/grid.json")
  .then((r) => {
    if (!r.ok) throw new Error(`grid.json: ${r.status}`);
    return r.json();
  })
  .then(init)
  .catch((e) => {
    const box = document.getElementById("error");
    box.hidden = false;
    box.textContent = "Could not load data/grid.json. Serve the docs folder over HTTP (for example: python -m http.server -d docs). " + e.message;
  });

function init({ features, levels, baseline_index: base, probs }) {
  // Row-major strides: the last feature varies fastest
  const strides = features.map((_, i) => levels.slice(i + 1).reduce((a, l) => a * l.length, 1));
  const lookup = (idx) => probs[idx.reduce((s, v, i) => s + v * strides[i], 0)] / 1000;
  const state = [...base];

  const fmtValue = (f, v) => (f === "avg_utilization_ratio" ? (v * 100).toFixed(0) + "%" : v.toLocaleString());
  const container = document.getElementById("sliders");

  features.forEach((f, i) => {
    const wrap = document.createElement("div");
    wrap.className = "slider";
    wrap.innerHTML = `<label><span>${NAMES[f]}</span><span id="v-${f}"></span></label>
      <input type="range" min="0" max="${levels[i].length - 1}" step="1" value="${state[i]}" aria-label="${NAMES[f]}">`;
    wrap.querySelector("input").addEventListener("input", (e) => {
      state[i] = Number(e.target.value);
      update();
    });
    container.appendChild(wrap);
  });

  const baseProb = lookup(base);
  document.getElementById("base-prob").textContent = (baseProb * 100).toFixed(1) + "%";

  function update() {
    features.forEach((f, i) => (document.getElementById(`v-${f}`).textContent = fmtValue(f, levels[i][state[i]])));

    const p = lookup(state);
    const probEl = document.getElementById("prob");
    const level = p >= 0.6 ? "High" : p >= 0.3 ? "Medium" : "Low";
    const color = { High: "var(--red)", Medium: "var(--amber)", Low: "var(--green)" }[level];
    probEl.textContent = (p * 100).toFixed(1) + "%";
    probEl.style.color = color;
    const levelEl = document.getElementById("level");
    levelEl.textContent = level + " risk";
    levelEl.style.color = color;

    // Impact of each feature versus the typical value, others held at the current profile
    const impacts = features
      .map((f, i) => {
        const alt = [...state];
        alt[i] = base[i];
        return { f, d: p - lookup(alt) };
      })
      .sort((a, b) => Math.abs(b.d) - Math.abs(a.d));
    const max = Math.max(0.05, ...impacts.map((x) => Math.abs(x.d)));

    document.getElementById("impact").innerHTML = impacts
      .map(({ f, d }) => {
        const w = (Math.abs(d) / max) * 50;
        const style = d >= 0 ? `left:50%;width:${w}%;background:var(--red)` : `left:${50 - w}%;width:${w}%;background:var(--green)`;
        const sign = d > 0 ? "+" : "";
        return `<div class="row"><span>${NAMES[f]}</span><div class="track"><div class="mid"></div><div class="fill" style="${style}"></div></div><span class="num">${sign}${(d * 100).toFixed(1)}</span></div>`;
      })
      .join("");
  }
  update();
}
