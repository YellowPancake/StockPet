"use strict";

const rowsElement = document.querySelector("#rows");
const boardElement = document.querySelector("#board");
const emptyElement = document.querySelector("#empty");
const alertElement = document.querySelector("#alert");
const mascotElement = document.querySelector("#mascot");
const alertTitleElement = document.querySelector("#alert-title");
const alertDetailElement = document.querySelector("#alert-detail");

const marketLabels = {
  aShare: "A股",
  hongKong: "港股",
  unitedStates: "美股",
};

let state = null;
let quotes = {};
let alertTimer = null;
let dragging = false;

function applyDisplayScale() {
  if (!state) return;
  const scale = Math.min(1.6, Math.max(0.65, Number(state.displayScale) || 1));
  document.body.style.width = `${window.innerWidth / scale}px`;
  document.body.style.height = `${window.innerHeight / scale}px`;
  document.body.style.transform = `scale(${scale})`;
}

function stockColor(market, change) {
  const rising = market === "unitedStates" ? "#55d69e" : "#ff6673";
  const falling = market === "unitedStates" ? "#ff6673" : "#55d69e";
  return change >= 0 ? rising : falling;
}

function escapeHTML(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function formatPrice(value) {
  if (!Number.isFinite(value)) return "—";
  return value >= 1000 ? value.toFixed(2) : value.toFixed(2);
}

function linePath(points, previousClose) {
  if (!Array.isArray(points) || points.length < 2) return "";
  const maxPoints = 260;
  const step = Math.max(1, Math.floor(points.length / maxPoints));
  const sampled = points.filter((_point, index) => index % step === 0);
  if (sampled.at(-1) !== points.at(-1)) sampled.push(points.at(-1));
  const values = sampled.map((point) => Number(point.price)).filter(Number.isFinite);
  if (Number.isFinite(previousClose)) values.push(previousClose);
  let min = Math.min(...values);
  let max = Math.max(...values);
  if (max === min) {
    max += 1;
    min -= 1;
  }
  const padding = (max - min) * 0.08;
  min -= padding;
  max += padding;
  return sampled
    .map((point, index) => {
      const x = (index / Math.max(1, sampled.length - 1)) * 100;
      const y = 44 - ((point.price - min) / (max - min)) * 40;
      return `${index ? "L" : "M"}${x.toFixed(2)},${y.toFixed(2)}`;
    })
    .join(" ");
}

function baselineY(quote) {
  if (!quote?.points?.length || !(quote.previousClose > 0)) return 23;
  const values = quote.points.map((point) => Number(point.price)).filter(Number.isFinite);
  values.push(quote.previousClose);
  let min = Math.min(...values);
  let max = Math.max(...values);
  if (max === min) return 23;
  const padding = (max - min) * 0.08;
  min -= padding;
  max += padding;
  return 44 - ((quote.previousClose - min) / (max - min)) * 40;
}

function render() {
  if (!state) return;
  applyDisplayScale();
  document.documentElement.style.setProperty("--line-opacity", state.lineOpacity);
  document.documentElement.style.setProperty("--label-opacity", state.labelOpacity);
  boardElement.style.background = `rgba(19, 22, 30, ${state.backgroundOpacity})`;
  alertElement.style.opacity = state.alertOpacity;
  emptyElement.hidden = state.symbols.length > 0;
  rowsElement.innerHTML = state.symbols.map((symbol) => {
    const quote = quotes[symbol.quoteID];
    const change = Number(quote?.changePercent || 0);
    const color = stockColor(symbol.market, change);
    const sign = change >= 0 ? "+" : "";
    const path = linePath(quote?.points, quote?.previousClose);
    const baseline = baselineY(quote);
    return `
      <article class="stock-row" style="--stock-color:${color}">
        <div class="identity">
          <div class="name">${escapeHTML(symbol.name)}</div>
          <div class="meta">
            <span>${escapeHTML(symbol.code)}</span>
            <span class="market">${marketLabels[symbol.market] || ""}</span>
          </div>
        </div>
        <svg class="chart ${path ? "" : "placeholder"}" viewBox="0 0 100 46" preserveAspectRatio="none">
          <line class="baseline" x1="0" y1="${baseline}" x2="100" y2="${baseline}"></line>
          ${path ? `<path class="line" d="${path}"></path>` : '<path class="line" d="M0,23 L100,23"></path>'}
          ${path ? `<circle class="dot" cx="100" cy="${path.split(",").at(-1)}" r="1.4"></circle>` : ""}
        </svg>
        <div class="price-block">
          <div class="last-price">${quote?.isStale ? '<span class="stale">⟳</span>' : ""}${formatPrice(quote?.lastPrice)}</div>
          <div class="percent">${quote ? `${sign}${change.toFixed(2)}%` : "加载中…"}</div>
        </div>
      </article>
    `;
  }).join("");
}

function playAlertSound(direction) {
  const file = direction === "rising" ? "bull-moo.wav" : "bear-growl.wav";
  const audio = new Audio(`assets/${file}`);
  audio.volume = 0.82;
  audio.play().catch(() => {});
}

function showAlert(alert) {
  clearTimeout(alertTimer);
  const rising = alert.direction === "rising";
  const currency = alert.symbol.market === "aShare"
    ? "¥"
    : alert.symbol.market === "hongKong" ? "HK$" : "$";
  mascotElement.textContent = rising ? "🐂" : "🐻";
  alertTitleElement.textContent = `${alert.symbol.name} ${rising ? "上涨提醒" : "下跌提醒"}`;
  alertDetailElement.textContent = alert.basis === "targetPrice" && alert.targetPrice > 0
    ? `现价 ${currency}${formatPrice(alert.lastPrice)} · 目标 ${currency}${formatPrice(alert.targetPrice)}`
    : `${alert.percent >= 0 ? "+" : ""}${alert.percent.toFixed(2)}%`;
  alertElement.hidden = false;
  if (alert.soundEnabled) playAlertSound(alert.direction);
  alertTimer = setTimeout(() => {
    alertElement.hidden = true;
  }, 6000);
}

boardElement.addEventListener("dblclick", (event) => {
  event.preventDefault();
  stopDragging();
  window.stockPet.openSettings();
});

boardElement.addEventListener("pointerdown", (event) => {
  if (event.button !== 0) return;
  dragging = true;
  boardElement.classList.add("dragging");
  boardElement.setPointerCapture(event.pointerId);
  window.stockPet.beginWindowDrag(event.screenX, event.screenY);
});

boardElement.addEventListener("pointermove", (event) => {
  if (!dragging) return;
  window.stockPet.dragWindow(event.screenX, event.screenY);
});

function stopDragging() {
  if (dragging) window.stockPet.endWindowDrag();
  dragging = false;
  boardElement.classList.remove("dragging");
}

boardElement.addEventListener("pointerup", stopDragging);
boardElement.addEventListener("pointercancel", stopDragging);
boardElement.addEventListener("lostpointercapture", stopDragging);
window.addEventListener("blur", stopDragging);
window.addEventListener("resize", applyDisplayScale);

window.stockPet.on("state-changed", (nextState) => {
  state = nextState;
  render();
});
window.stockPet.on("quotes-updated", (nextQuotes) => {
  quotes = nextQuotes;
  render();
});
window.stockPet.on("stock-alert", showAlert);
window.stockPet.on("alert-dismiss", () => {
  clearTimeout(alertTimer);
  alertElement.hidden = true;
});

window.stockPet.bootstrap().then((snapshot) => {
  state = snapshot.state;
  quotes = snapshot.quotes;
  render();
});
