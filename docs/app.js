// India Air Quality Monitor — client-side.
// Loads pre-computed JSON from /data and renders the dashboard.

const CATEGORY_COLORS = {
  "Good":         "#8FBF3B",
  "Satisfactory": "#B8D651",
  "Moderate":     "#F5C24F",
  "Poor":         "#EE8A3A",
  "Very Poor":    "#D3492A",
  "Severe":       "#7A1A1A",
  "Unknown":      "#9AA0A6",
};

const $ = (sel) => document.querySelector(sel);

// ---------- Utilities ----------

async function fetchJSON(path) {
  const res = await fetch(path, { cache: "no-cache" });
  if (!res.ok) throw new Error(`${path}: ${res.status}`);
  return res.json();
}

function fmtTimestamp(iso) {
  const d = new Date(iso.replace(" ", "T") + "Z");
  return d.toLocaleString(undefined, {
    year: "numeric", month: "short", day: "2-digit",
    hour: "2-digit", minute: "2-digit",
    hour12: false,
  }) + " local";
}

function fmtHoursAgo(iso) {
  const d = new Date(iso.replace(" ", "T") + "Z");
  const diffMin = Math.round((Date.now() - d.getTime()) / 60000);
  if (diffMin < 1)  return "just now";
  if (diffMin < 60) return `${diffMin} min ago`;
  const h = Math.round(diffMin / 60);
  if (h < 24)  return `${h} hr ago`;
  return `${Math.round(h / 24)} d ago`;
}

// ---------- Renderers ----------

function renderHero(latest) {
  if (!latest.length) return;
  const worst = latest[0];  // API returns sorted DESC by naqi
  $("#hero-city").textContent = worst.city_name;
  $("#hero-number").textContent = worst.naqi_pm25;
  $("#hero-category").textContent = worst.category;
  const color = CATEGORY_COLORS[worst.category] ?? CATEGORY_COLORS.Unknown;
  $("#hero-glow").style.background =
    `radial-gradient(closest-side, ${color} 0%, transparent 70%)`;
}

function sparklineSVG(values, colour) {
  if (!values.length) return "";
  const w = 100, h = 30;
  const min = Math.min(...values);
  const max = Math.max(...values);
  const range = Math.max(max - min, 1);
  const pts = values.map((v, i) => {
    const x = (i / (values.length - 1)) * w;
    const y = h - ((v - min) / range) * h;
    return `${x.toFixed(1)},${y.toFixed(1)}`;
  }).join(" ");
  return `
    <svg viewBox="0 0 ${w} ${h}" preserveAspectRatio="none">
      <polyline
        fill="none"
        stroke="${colour}"
        stroke-width="1.5"
        stroke-linejoin="round"
        stroke-linecap="round"
        points="${pts}"
        vector-effect="non-scaling-stroke"
      />
    </svg>
  `;
}

function renderCards(latest, hourly) {
  const container = $("#city-cards");
  container.innerHTML = "";

  // Group hourly data by city for sparkline lookup.
  const bySlug = new Map();
  for (const row of hourly) {
    if (!bySlug.has(row.city_slug)) bySlug.set(row.city_slug, []);
    bySlug.get(row.city_slug).push(row);
  }

  for (const row of latest) {
    const colour = CATEGORY_COLORS[row.category] ?? CATEGORY_COLORS.Unknown;
    const sparkVals = (bySlug.get(row.city_slug) ?? []).map(r => r.naqi_pm25);

    const card = document.createElement("article");
    card.className = "card";
    card.innerHTML = `
      <div class="card-top">
        <div class="card-city">${row.city_name}</div>
        <div class="card-state">${row.state}</div>
      </div>
      <div class="card-reading">
        <div class="card-naqi">${row.naqi_pm25}</div>
        <div class="card-pm">PM2.5 &nbsp;${row.pm2_5} µg/m³</div>
      </div>
      <div class="card-category-bar" style="background:${colour}"></div>
      <div class="card-category-label">
        <span>${row.category}</span>
        <span>${fmtHoursAgo(row.ts_utc)}</span>
      </div>
      <div class="card-spark">${sparklineSVG(sparkVals, colour)}</div>
    `;
    container.appendChild(card);
  }
}

function renderTrend(hourly) {
  const cities = [...new Set(hourly.map(r => r.city_slug))];

  // Build one dataset per city.
  const palette = [
    "#E8E4D9", "#F5C24F", "#EE8A3A", "#8FBF3B", "#9AA0A6", "#D3492A",
  ];
  const datasets = cities.map((slug, i) => {
    const rows = hourly.filter(r => r.city_slug === slug);
    const label = rows[0]?.city_name ?? slug;
    return {
      label,
      data: rows.map(r => ({
        x: new Date(r.ts_utc.replace(" ", "T") + "Z"),
        y: r.naqi_pm25,
      })),
      borderColor: palette[i % palette.length],
      backgroundColor: palette[i % palette.length],
      borderWidth: 1.5,
      pointRadius: 0,
      pointHoverRadius: 4,
      tension: 0.2,
    };
  });

  const ctx = $("#trend-chart").getContext("2d");
  const chart = new Chart(ctx, {
    type: "line",
    data: { datasets },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      interaction: { mode: "index", intersect: false },
      plugins: {
        legend: {
          labels: {
            color: "#a4adb8",
            font: { family: "'IBM Plex Mono', monospace", size: 11 },
            boxWidth: 8, boxHeight: 8,
            usePointStyle: true,
          },
        },
        tooltip: {
          backgroundColor: "#0f1620",
          borderColor: "#3a4756",
          borderWidth: 1,
          titleFont: { family: "'IBM Plex Mono', monospace", size: 11 },
          bodyFont:  { family: "'IBM Plex Mono', monospace", size: 11 },
          padding: 10,
          callbacks: {
            title: (items) => items[0].parsed.x
              ? new Date(items[0].parsed.x).toLocaleString(undefined, {
                  month: "short", day: "2-digit", hour: "2-digit", minute: "2-digit",
                })
              : "",
            label: (item) => `${item.dataset.label}: NAQI ${Math.round(item.parsed.y)}`,
          },
        },
      },
      scales: {
        x: {
          type: "time",
          time: { unit: "day", tooltipFormat: "PP HH:mm" },
          ticks: {
            color: "#6b7683",
            font: { family: "'IBM Plex Mono', monospace", size: 10 },
          },
          grid: { color: "#2a3441", drawTicks: false },
          border: { color: "#3a4756" },
        },
        y: {
          beginAtZero: true,
          ticks: {
            color: "#6b7683",
            font: { family: "'IBM Plex Mono', monospace", size: 10 },
            stepSize: 100,
          },
          grid: { color: "#2a3441", drawTicks: false },
          border: { color: "#3a4756" },
        },
      },
    },
  });

  // Toggle chips: click to hide/show each city.
  const controls = $("#trend-controls");
  controls.innerHTML = "";
  chart.data.datasets.forEach((ds, i) => {
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "trend-toggle";
    btn.textContent = ds.label;
    btn.setAttribute("aria-pressed", "true");
    btn.addEventListener("click", () => {
      const hidden = chart.getDatasetMeta(i).hidden;
      chart.getDatasetMeta(i).hidden = !hidden;
      btn.setAttribute("aria-pressed", hidden ? "true" : "false");
      chart.update();
    });
    controls.appendChild(btn);
  });
}

function renderLastUpdate(latest) {
  if (!latest.length) return;
  // Pick the most recent timestamp across all cities.
  const iso = latest
    .map(r => r.ts_utc)
    .sort()
    .at(-1);
  $("#last-update").textContent = fmtTimestamp(iso);
}

// ---------- Boot ----------

function safe(fn, label) {
  try { fn(); }
  catch (err) { console.error(`${label} failed:`, err); }
}

(async () => {
  let latest = [], hourly = [];
  try {
    [latest, hourly] = await Promise.all([
      fetchJSON("data/latest.json"),
      fetchJSON("data/hourly_trend.json"),
    ]);
  } catch (err) {
    console.error("Data load failed:", err);
    $("#city-cards").innerHTML =
      `<p style="color:var(--text-muted);font-family:var(--font-mono);font-size:.85rem">
         Couldn't load data — the pipeline may still be waiting for its first run.
       </p>`;
    return;
  }

  // Each section renders independently: a broken chart shouldn't hide the cards.
  safe(() => renderLastUpdate(latest), "renderLastUpdate");
  safe(() => renderHero(latest),       "renderHero");
  safe(() => renderCards(latest, hourly), "renderCards");

  // Chart.js is loaded from a CDN — degrade gracefully if it didn't arrive.
  if (typeof Chart === "undefined") {
    $("#trend-chart").replaceWith(Object.assign(document.createElement("p"), {
      textContent: "Chart library unavailable — see docs/data/hourly_trend.json for raw values.",
      style: "color:var(--text-muted);font-family:var(--font-mono);font-size:.85rem;padding:2rem",
    }));
  } else {
    safe(() => renderTrend(hourly), "renderTrend");
  }
})();
