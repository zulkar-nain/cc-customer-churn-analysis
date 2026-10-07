const pct = (x) => (x * 100).toFixed(1) + "%";
const fmt = (x) => (typeof x === "number" ? (Number.isInteger(x) ? x.toLocaleString() : x.toFixed(3)) : x);

async function load(path) {
  const res = await fetch(path);
  if (!res.ok) throw new Error(`${path}: ${res.status}`);
  return res.json();
}

function renderMetrics(summary) {
  const labels = {
    roc_auc: ["ROC-AUC", "Ranking quality"],
    pr_auc: ["PR-AUC", "Precision vs. recall"],
    accuracy: ["Accuracy", "Share correct"],
    recall: ["Recall", "Churners caught"],
    precision: ["Precision", "Alerts that were right"],
  };
  document.getElementById("metric-cards").innerHTML = Object.entries(labels)
    .map(([key, [name, hint]]) => `<div class="card"><h3>${name}</h3><div class="metric">${summary.metrics[key].toFixed(3)}</div><p class="hint">${hint}</p></div>`)
    .join("");
  document.getElementById("churn-rate").textContent = pct(summary.churn_rate);
}

function renderConfusion({ confusion: c }) {
  document.getElementById("cm").innerHTML = `
    <div class="h"></div><div class="h">Pred. churned</div><div class="h">Pred. active</div>
    <div class="h">Actually churned</div><div class="good">${c.tp}</div><div class="bad">${c.fn}</div>
    <div class="h">Actually active</div><div class="bad">${c.fp}</div><div class="good">${c.tn}</div>`;
}

function renderBands({ risk_bands: b, n_test: n }) {
  const colors = { Low: "var(--green)", Medium: "var(--amber)", High: "var(--red)" };
  document.getElementById("bands").innerHTML = ["Low", "Medium", "High"]
    .map((k) => `<div class="row"><span class="label">${k}</span><div class="track"><div class="fill" style="width:${(b[k] / n) * 100}%;background:${colors[k]}"></div></div><span class="val">${b[k]} (${pct(b[k] / n)})</span></div>`)
    .join("");
}

function renderCards(rows) {
  const chips = (r) => [
    ["Age", r.customer_age],
    ["Transactions", r.total_trans_ct],
    ["Inactive", r.months_inactive_12_mon + " mo"],
    ["Utilization", pct(r.avg_utilization_ratio)],
    ["Products", r.total_relationship_count],
    ["Contacts", r.contacts_count_12_mon],
  ].map(([k, v]) => `<span class="chip"><b>${v}</b> ${k}</span>`).join("");

  document.getElementById("risk-cards").innerHTML = rows.slice(0, 6).map((r, i) => `
    <div class="card risk-card">
      <div class="ring" style="--p:${r.churn_probability * 100}"><span>${Math.round(r.churn_probability * 100)}%</span></div>
      <div>
        <div class="rc-title">Customer #${i + 1} <span class="pill ${r.risk}">${r.risk}</span></div>
        <div class="chips">${chips(r)}</div>
        <div class="hint">${r.actual === "Churned" ? "Actually left" : "Actually stayed"}</div>
      </div>
    </div>`).join("");
}

function renderTable(rows) {
  const table = document.getElementById("top-table");
  const cols = Object.keys(rows[0]);
  let sort = { col: "churn_probability", dir: -1 };

  const draw = () => {
    const sorted = [...rows].sort((a, b) => (a[sort.col] > b[sort.col] ? 1 : a[sort.col] < b[sort.col] ? -1 : 0) * sort.dir);
    table.innerHTML =
      `<thead><tr>${cols.map((c) => `<th data-col="${c}">${c.replaceAll("_", " ")}${sort.col === c ? (sort.dir > 0 ? " ▲" : " ▼") : ""}</th>`).join("")}</tr></thead>` +
      `<tbody>${sorted.map((r) => `<tr>${cols.map((c) => `<td>${c === "risk" ? `<span class="pill ${r[c]}">${r[c]}</span>` : fmt(r[c])}</td>`).join("")}</tr>`).join("")}</tbody>`;
    table.querySelectorAll("th").forEach((th) =>
      th.addEventListener("click", () => {
        const col = th.dataset.col;
        sort = { col, dir: sort.col === col ? -sort.dir : -1 };
        draw();
      }));
  };
  draw();
}

function initLightbox() {
  const box = document.createElement("div");
  box.className = "lightbox";
  box.setAttribute("role", "dialog");
  box.setAttribute("aria-modal", "true");
  box.innerHTML = '<button class="close" aria-label="Close image">&times;</button><img alt="">';
  document.body.appendChild(box);
  const big = box.querySelector("img");
  let opener = null;

  const close = () => {
    box.classList.remove("open");
    document.body.classList.remove("no-scroll");
    if (opener) opener.focus();
  };
  const open = (img) => {
    opener = img;
    big.src = img.src;
    big.alt = img.alt;
    box.classList.add("open");
    document.body.classList.add("no-scroll");
    box.querySelector(".close").focus();
  };

  document.querySelectorAll(".card img").forEach((img) => {
    img.dataset.zoom = "";
    img.tabIndex = 0;
    img.title = "Click to enlarge";
    img.addEventListener("click", () => open(img));
    img.addEventListener("keydown", (e) => (e.key === "Enter" || e.key === " ") && (e.preventDefault(), open(img)));
  });
  box.addEventListener("click", close);
  document.addEventListener("keydown", (e) => e.key === "Escape" && box.classList.contains("open") && close());
}

initLightbox();

(async () => {
  try {
    const [summary, top] = await Promise.all([load("data/summary.json"), load("data/top_risk.json")]);
    renderMetrics(summary);
    renderConfusion(summary);
    renderBands(summary);
    renderTable(top);
    renderCards(top);
  } catch (e) {
    const box = document.getElementById("error");
    box.hidden = false;
    box.textContent = "Could not load data files. Serve the docs folder over HTTP (for example: python -m http.server -d docs). " + e.message;
  }
})();
