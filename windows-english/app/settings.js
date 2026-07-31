"use strict";

const marketLabels = {
  aShare: "A-share",
  hongKong: "HK",
  unitedStates: "US",
};

let state = null;
let status = null;
let quotes = {};
let searchResults = [];

const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => [...document.querySelectorAll(selector)];

function escapeHTML(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function switchPage(name) {
  $$(".nav-item").forEach((item) => item.classList.toggle("active", item.dataset.page === name));
  $$(".page").forEach((page) => page.classList.toggle("active", page.id === `page-${name}`));
}

function renderStocks() {
  if (!state) return;
  $("#stock-count").textContent = `${state.symbols.length} stocks`;
  $("#current-stocks").innerHTML = state.symbols.length
    ? state.symbols.map((symbol, index) => `
        <div class="stock-item">
          <div>
            <div class="stock-name">${escapeHTML(symbol.name)}</div>
            <div class="stock-meta">${escapeHTML(symbol.code)} · ${marketLabels[symbol.market]}</div>
          </div>
          <div class="stock-actions">
            <button data-action="up" data-id="${escapeHTML(symbol.quoteID)}" ${index === 0 ? "disabled" : ""} title="Move up">↑</button>
            <button data-action="down" data-id="${escapeHTML(symbol.quoteID)}" ${index === state.symbols.length - 1 ? "disabled" : ""} title="Move down">↓</button>
            <button class="remove" data-action="remove" data-id="${escapeHTML(symbol.quoteID)}" title="Remove">×</button>
          </div>
        </div>
      `).join("")
    : '<div class="empty-list">No stocks are on your desktop yet</div>';
}

function renderSearchResults() {
  $("#search-results").innerHTML = searchResults.map((symbol, index) => `
    <div class="search-result">
      <div>
        <div class="result-name">${escapeHTML(symbol.name)}</div>
        <div class="result-meta">${escapeHTML(symbol.code)} · ${marketLabels[symbol.market]}</div>
      </div>
      <button class="small-button" data-add-index="${index}">Add</button>
    </div>
  `).join("");
}

function formatLivePrice(symbol, price) {
  if (!(Number(price) > 0)) return "Waiting for live price";
  const currency = symbol.market === "aShare" ? "¥" : symbol.market === "hongKong" ? "HK$" : "$";
  return `Live ${currency}${Number(price).toFixed(2)}`;
}

function renderPriceAlerts() {
  if (!state) return;
  const list = $("#price-alert-list");
  list.innerHTML = state.symbols.length
    ? state.symbols.map((symbol) => {
        const quote = quotes[symbol.quoteID];
        const targets = state.priceAlertTargets[symbol.quoteID] || {
          risingPrice: 0,
          fallingPrice: 0,
        };
        const enabled = targets.risingPrice > 0 || targets.fallingPrice > 0;
        return `
          <div class="price-alert-item" data-price-alert-id="${escapeHTML(symbol.quoteID)}">
            <div class="price-alert-heading">
              <input class="switch price-alert-enabled" type="checkbox" ${enabled ? "checked" : ""} ${quote?.lastPrice > 0 || enabled ? "" : "disabled"} />
              <div>
                <div class="stock-name">${escapeHTML(symbol.name)}</div>
                <div class="stock-meta">${escapeHTML(symbol.code)} · ${marketLabels[symbol.market]}</div>
              </div>
              <div class="live-price">${formatLivePrice(symbol, quote?.lastPrice)}</div>
            </div>
            <div class="price-target-fields">
              <label class="price-target-field">🐂 Bull target ≥
                <input class="rising-price-target" type="number" min="0" step="0.01" value="${enabled ? targets.risingPrice.toFixed(2) : ""}" ${enabled ? "" : "disabled"} />
              </label>
              <label class="price-target-field">🐻 Bear target ≤
                <input class="falling-price-target" type="number" min="0" step="0.01" value="${enabled ? targets.fallingPrice.toFixed(2) : ""}" ${enabled ? "" : "disabled"} />
              </label>
            </div>
          </div>
        `;
      }).join("")
    : '<div class="empty-list">Add stocks to the Watchlist first</div>';
}

function syncControls() {
  if (!state) return;
  const ranges = {
    displayScale: `${Math.round(state.displayScale * 100)}%`,
    lineOpacity: `${Math.round(state.lineOpacity * 100)}%`,
    labelOpacity: `${Math.round(state.labelOpacity * 100)}%`,
    backgroundOpacity: `${Math.round(state.backgroundOpacity * 100)}%`,
    alertOpacity: `${Math.round(state.alertOpacity * 100)}%`,
  };
  for (const [id, text] of Object.entries(ranges)) {
    const input = $(`#${id}`);
    input.value = state[id];
    input.parentElement.querySelector("output").textContent = text;
  }
  for (const id of [
    "alwaysOnTop",
    "clickThrough",
    "bullSoundEnabled",
    "bearSoundEnabled",
    "alertsEnabled",
    "shortcutEnabled",
  ]) {
    $(`#${id}`).checked = state[id];
  }
  $("#shortcutModifier").value = state.shortcutModifier;
  $("#shortcutKey").value = state.shortcutKey;
  $("#shortcut-options").classList.toggle("disabled", !state.shortcutEnabled);
  $("#shortcutModifier").disabled = !state.shortcutEnabled;
  $("#shortcutKey").disabled = !state.shortcutEnabled;
  $("#alertBasis").value = state.alertBasis;
  const targetMode = state.alertBasis === "targetPrice";
  $("#percentage-alert-controls").hidden = targetMode;
  $("#price-alert-controls").hidden = !targetMode;
  $("#alert-basis-description").textContent = targetMode
    ? "Set a bull and bear target for each stock and get alerted when the live price reaches it"
    : "Changes are measured from the previous close; each crossing alerts once";
  $("#alert-rearm-tip").textContent = targetMode
    ? "After a target alert, the price must move at least 0.15% back inside the target before re-arming. Quotes keep updating at the selected refresh interval."
    : "Alerts re-arm after the change returns at least 0.15 percentage points inside the threshold, preventing repeated alerts near the boundary.";
  $("#risingThreshold").value = state.risingThreshold;
  $("#fallingThreshold").value = state.fallingThreshold;
  $("#refreshInterval").value = String(state.refreshInterval);
  renderStocks();
  renderPriceAlerts();
  for (const control of $$("#page-alerts input, #page-alerts select, #page-alerts button")) {
    if (control.id === "alertsEnabled") continue;
    const item = control.closest("[data-price-alert-id]");
    const ruleEnabled = item?.querySelector(".price-alert-enabled")?.checked ?? true;
    const quoteID = item?.dataset.priceAlertId;
    const hasLivePrice = quoteID ? quotes[quoteID]?.lastPrice > 0 : true;
    const unavailable = control.classList.contains("price-alert-enabled")
      ? !hasLivePrice && !ruleEnabled
      : (control.classList.contains("rising-price-target")
        || control.classList.contains("falling-price-target"))
        ? !ruleEnabled
        : false;
    control.disabled = !state.alertsEnabled || unavailable;
  }
}

function renderStatus() {
  if (!status) return;
  $("#data-source").textContent = status.source || "Tencent intraday · Eastmoney fallback";
  $("#last-refresh").textContent = status.lastRefresh
    ? new Date(status.lastRefresh).toLocaleString("en-US")
    : "Not refreshed yet";
  const error = $("#source-error");
  error.hidden = !status.sourceError;
  error.textContent = status.sourceError || "";
}

async function updateState(patch) {
  state = await window.stockPet.updateState(patch);
  syncControls();
}

$$(".nav-item").forEach((item) => {
  item.addEventListener("click", () => switchPage(item.dataset.page));
});

$("#search-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const query = $("#search-input").value.trim();
  if (!query) return;
  $("#search-message").textContent = "Searching…";
  searchResults = [];
  renderSearchResults();
  try {
    searchResults = await window.stockPet.search(query);
    $("#search-message").textContent = searchResults.length
      ? ""
      : "No supported A-share, Hong Kong, or US stock was found";
  } catch (error) {
    $("#search-message").textContent = error.message || "Search is temporarily unavailable";
  }
  renderSearchResults();
});

$("#search-results").addEventListener("click", async (event) => {
  const button = event.target.closest("[data-add-index]");
  if (!button) return;
  const symbol = searchResults[Number(button.dataset.addIndex)];
  if (!symbol) return;
  const result = await window.stockPet.addSymbol(symbol);
  $("#search-message").textContent = result.ok ? `${symbol.name} added` : result.message;
});

$("#current-stocks").addEventListener("click", async (event) => {
  const button = event.target.closest("[data-action]");
  if (!button) return;
  const { action, id } = button.dataset;
  if (action === "remove") await window.stockPet.removeSymbol(id);
  if (action === "up") await window.stockPet.moveSymbol(id, -1);
  if (action === "down") await window.stockPet.moveSymbol(id, 1);
});

for (const id of ["displayScale", "lineOpacity", "labelOpacity", "backgroundOpacity", "alertOpacity"]) {
  const input = $(`#${id}`);
  input.addEventListener("input", () => {
    const value = Number(input.value);
    input.parentElement.querySelector("output").textContent = `${Math.round(value * 100)}%`;
  });
  input.addEventListener("change", () => updateState({ [id]: Number(input.value) }));
}

for (const id of [
  "alwaysOnTop",
  "clickThrough",
  "bullSoundEnabled",
  "bearSoundEnabled",
  "alertsEnabled",
  "shortcutEnabled",
]) {
  $(`#${id}`).addEventListener("change", (event) => updateState({ [id]: event.target.checked }));
}

for (const id of ["shortcutModifier", "shortcutKey"]) {
  $(`#${id}`).addEventListener("change", (event) => updateState({ [id]: event.target.value }));
}

$("#alertBasis").addEventListener("change", (event) => {
  updateState({ alertBasis: event.target.value });
});

for (const id of ["risingThreshold", "fallingThreshold"]) {
  $(`#${id}`).addEventListener("change", (event) => updateState({ [id]: Number(event.target.value) }));
}

$("#refreshInterval").addEventListener("change", (event) => {
  updateState({ refreshInterval: Number(event.target.value) });
});

$("#reset-appearance").addEventListener("click", () => updateState({
  displayScale: 1,
  lineOpacity: 0.92,
  labelOpacity: 0.92,
  backgroundOpacity: 0.16,
}));

$("#preview-bull").addEventListener("click", () => window.stockPet.previewAlert("rising"));
$("#preview-bear").addEventListener("click", () => window.stockPet.previewAlert("falling"));

$("#price-alert-list").addEventListener("change", async (event) => {
  const item = event.target.closest("[data-price-alert-id]");
  if (!item) return;
  const quoteID = item.dataset.priceAlertId;
  const symbol = state.symbols.find((candidate) => candidate.quoteID === quoteID);
  if (!symbol) return;
  const nextTargets = { ...state.priceAlertTargets };
  const quote = quotes[quoteID];

  if (event.target.classList.contains("price-alert-enabled")) {
    if (!event.target.checked) {
      delete nextTargets[quoteID];
    } else if (quote?.lastPrice > 0) {
      nextTargets[quoteID] = {
        risingPrice: quote.lastPrice * (1 + state.risingThreshold / 100),
        fallingPrice: quote.lastPrice * (1 - state.fallingThreshold / 100),
      };
    }
  } else {
    const current = nextTargets[quoteID] || { risingPrice: 0, fallingPrice: 0 };
    if (event.target.classList.contains("rising-price-target")) {
      current.risingPrice = Number(event.target.value);
    }
    if (event.target.classList.contains("falling-price-target")) {
      current.fallingPrice = Number(event.target.value);
    }
    nextTargets[quoteID] = current;
  }
  await updateState({ priceAlertTargets: nextTargets });
});

$("#refresh-alert-prices").addEventListener("click", async () => {
  $("#price-alert-message").textContent = "Refreshing live prices…";
  const snapshot = await window.stockPet.refresh();
  quotes = snapshot.quotes || {};
  status = snapshot.status;
  $("#price-alert-message").textContent = "Live prices refreshed";
  renderPriceAlerts();
  renderStatus();
});

$("#generate-price-targets").addEventListener("click", async () => {
  $("#price-alert-message").textContent = "Refreshing and generating targets…";
  const snapshot = await window.stockPet.refresh();
  quotes = snapshot.quotes || {};
  status = snapshot.status;
  const nextTargets = { ...state.priceAlertTargets };
  let count = 0;
  for (const symbol of state.symbols) {
    const quote = quotes[symbol.quoteID];
    if (!(quote?.lastPrice > 0)) continue;
    nextTargets[symbol.quoteID] = {
      risingPrice: quote.lastPrice * (1 + state.risingThreshold / 100),
      fallingPrice: quote.lastPrice * (1 - state.fallingThreshold / 100),
    };
    count += 1;
  }
  await updateState({ priceAlertTargets: nextTargets });
  $("#price-alert-message").textContent = `Targets generated from live prices for ${count} stocks`;
  renderStatus();
});

$("#refresh-now").addEventListener("click", async (event) => {
  const button = event.currentTarget;
  button.disabled = true;
  button.textContent = "Refreshing…";
  const snapshot = await window.stockPet.refresh();
  status = snapshot.status;
  renderStatus();
  button.disabled = false;
  button.textContent = "Refresh all stocks now";
});

window.stockPet.on("state-changed", (nextState) => {
  state = nextState;
  syncControls();
});
window.stockPet.on("refresh-status", (nextStatus) => {
  status = nextStatus;
  renderStatus();
});
window.stockPet.on("quotes-updated", (nextQuotes) => {
  quotes = nextQuotes || {};
  renderPriceAlerts();
});

window.stockPet.bootstrap().then((snapshot) => {
  state = snapshot.state;
  quotes = snapshot.quotes || {};
  status = snapshot.status;
  syncControls();
  renderStatus();
});
