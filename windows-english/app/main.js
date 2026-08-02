"use strict";

const {
  app,
  BrowserWindow,
  globalShortcut,
  ipcMain,
  Menu,
  nativeImage,
  screen,
  shell,
  Tray,
} = require("electron");
const fs = require("node:fs");
const path = require("node:path");
const {
  evaluatePriceThreshold,
  evaluateThreshold,
  overlayDragPosition,
  overlayGeometry,
  sanitizeState,
} = require("./lib");
const { fetchIntraday, searchStocks } = require("./quote-service");

// Keep the English edition's defaults and preferences independent from the
// Chinese edition, even when both are installed on the same Windows account.
app.setPath("userData", path.join(app.getPath("appData"), "StockPet-English"));

let overlayWindow = null;
let settingsWindow = null;
let tray = null;
let refreshTimer = null;
let state = sanitizeState();
let quotes = {};
let quoteCache = {};
let thresholdStates = {};
let lastRefresh = null;
let sourceError = null;
let quitting = false;
let overlayDragStart = null;

const statePath = () => path.join(app.getPath("userData"), "settings.json");
const quoteCachePath = () => path.join(app.getPath("userData"), "quote-cache.json");
const assetPath = (name) => path.join(__dirname, "assets", name);

function readJSON(filePath, fallback) {
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch {
    return fallback;
  }
}

function writeJSON(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, JSON.stringify(value, null, 2), "utf8");
}

function loadData() {
  state = sanitizeState(readJSON(statePath(), {}));
  quoteCache = readJSON(quoteCachePath(), {});
  quotes = { ...quoteCache };
}

function persistState() {
  writeJSON(statePath(), state);
}

function persistQuotes() {
  writeJSON(quoteCachePath(), quoteCache);
}

function snapshot() {
  return {
    state,
    quotes,
    status: {
      lastRefresh,
      sourceError,
      source: "Tencent intraday · Eastmoney fallback",
    },
  };
}

function send(channel, payload) {
  for (const window of [overlayWindow, settingsWindow]) {
    if (window && !window.isDestroyed() && window.webContents) {
      window.webContents.send(channel, payload);
    }
  }
}

function updateOverlayGeometry() {
  if (!overlayWindow || overlayWindow.isDestroyed()) return;
  const display = screen.getDisplayMatching(overlayWindow.getBounds());
  const maximumHeight = Math.floor(display.workAreaSize.height * 0.84);
  const geometry = overlayGeometry(state.symbols.length, state.displayScale, maximumHeight);
  overlayWindow.webContents.setZoomFactor(1);
  overlayWindow.setSize(geometry.width, geometry.height, true);
  overlayWindow.setAlwaysOnTop(state.alwaysOnTop, "floating");
  overlayWindow.setIgnoreMouseEvents(state.clickThrough);
}

function notifyStateChanged() {
  updateOverlayGeometry();
  send("state-changed", state);
  rebuildTrayMenu();
}

function toggleOverlay() {
  if (!overlayWindow) return;
  overlayWindow.isVisible() ? overlayWindow.hide() : overlayWindow.showInactive();
  rebuildTrayMenu();
}

function registerGlobalShortcut() {
  globalShortcut.unregisterAll();
  if (!state.shortcutEnabled) return;
  globalShortcut.register(
    `${state.shortcutModifier}+${state.shortcutKey}`,
    toggleOverlay,
  );
}

function createOverlayWindow() {
  overlayWindow = new BrowserWindow({
    width: 860,
    height: 272,
    minWidth: 540,
    minHeight: 72,
    frame: false,
    transparent: true,
    backgroundColor: "#00000000",
    resizable: false,
    movable: false,
    alwaysOnTop: state.alwaysOnTop,
    skipTaskbar: true,
    show: false,
    hasShadow: false,
    icon: assetPath("app-icon.ico"),
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });
  overlayWindow.setMenuBarVisibility(false);
  overlayWindow.loadFile(path.join(__dirname, "overlay.html"));
  overlayWindow.once("ready-to-show", () => {
    updateOverlayGeometry();
    overlayWindow.showInactive();
  });
  overlayWindow.on("closed", () => {
    overlayDragStart = null;
    overlayWindow = null;
  });
}

function openSettings() {
  if (settingsWindow && !settingsWindow.isDestroyed()) {
    settingsWindow.show();
    settingsWindow.focus();
    return;
  }
  settingsWindow = new BrowserWindow({
    width: 1040,
    height: 780,
    minWidth: 900,
    minHeight: 680,
    title: "Stock Pet Settings",
    backgroundColor: "#f6f7fb",
    icon: assetPath("app-icon.ico"),
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
    },
  });
  settingsWindow.setMenuBarVisibility(false);
  settingsWindow.loadFile(path.join(__dirname, "settings.html"));
  settingsWindow.on("closed", () => {
    settingsWindow = null;
  });
}

function rebuildTrayMenu() {
  if (!tray) return;
  tray.setContextMenu(Menu.buildFromTemplate([
    {
      label: overlayWindow?.isVisible() ? "Hide Stock Pet" : "Show Stock Pet",
      click: toggleOverlay,
    },
    { label: "Refresh now", click: () => refreshAll() },
    {
      label: "Lock and ignore mouse events",
      type: "checkbox",
      checked: state.clickThrough,
      click: (item) => applyStatePatch({ clickThrough: item.checked }),
    },
    {
      label: "Always on top",
      type: "checkbox",
      checked: state.alwaysOnTop,
      click: (item) => applyStatePatch({ alwaysOnTop: item.checked }),
    },
    { type: "separator" },
    { label: "Settings…", click: openSettings },
    { type: "separator" },
    {
      label: "Quit Stock Pet",
      click: () => {
        quitting = true;
        app.quit();
      },
    },
  ]));
}

function createTray() {
  const trayImage = nativeImage.createFromPath(assetPath("icon-32.png"));
  tray = new Tray(trayImage);
  tray.setToolTip("Stock Pet");
  tray.on("double-click", openSettings);
  rebuildTrayMenu();
}

function resetRefreshTimer() {
  if (refreshTimer) clearInterval(refreshTimer);
  refreshTimer = setInterval(refreshAll, state.refreshInterval * 1000);
}

function applyStatePatch(patch) {
  const previousRefreshInterval = state.refreshInterval;
  const shortcutChanged = (
    patch.shortcutEnabled !== undefined ||
    patch.shortcutModifier !== undefined ||
    patch.shortcutKey !== undefined
  );
  state = sanitizeState({ ...state, ...patch });
  thresholdStates = {};
  persistState();
  notifyStateChanged();
  if (!state.alertsEnabled) send("alert-dismiss", null);
  if (shortcutChanged) registerGlobalShortcut();
  if (state.refreshInterval !== previousRefreshInterval) resetRefreshTimer();
  return state;
}

function presentAlert(direction, quote, preview = false) {
  const fallbackSymbol = state.symbols[0] || {
    code: "DEMO",
    name: "Preview",
    market: "aShare",
    quoteID: "preview",
  };
  const symbol = quote?.symbol || fallbackSymbol;
  const targets = state.priceAlertTargets[symbol.quoteID] || {};
  const targetPrice = direction === "rising" ? targets.risingPrice : targets.fallingPrice;
  const percent = quote?.changePercent
    ?? (direction === "rising" ? state.risingThreshold : -state.fallingThreshold);
  send("stock-alert", {
    direction,
    symbol,
    percent,
    basis: state.alertBasis,
    lastPrice: quote?.lastPrice ?? targetPrice ?? 0,
    targetPrice: state.alertBasis === "targetPrice" ? targetPrice : null,
    preview,
    soundEnabled: direction === "rising" ? state.bullSoundEnabled : state.bearSoundEnabled,
  });
}

function evaluateQuoteAlert(quote) {
  if (!state.alertsEnabled) return;
  const previous = thresholdStates[quote.symbol.quoteID] || "armed";
  const targets = state.priceAlertTargets[quote.symbol.quoteID];
  const result = state.alertBasis === "targetPrice"
    ? targets
      ? evaluatePriceThreshold(
          previous,
          quote.lastPrice,
          targets.risingPrice,
          targets.fallingPrice,
        )
      : { state: "armed", direction: null }
    : evaluateThreshold(
        previous,
        quote.changePercent,
        state.risingThreshold,
        state.fallingThreshold,
      );
  thresholdStates[quote.symbol.quoteID] = result.state;
  if (result.direction) presentAlert(result.direction, quote);
}

async function refreshAll() {
  const symbols = [...state.symbols];
  if (!symbols.length) {
    lastRefresh = new Date().toISOString();
    sourceError = null;
    send("refresh-status", snapshot().status);
    return snapshot();
  }
  const results = await Promise.allSettled(symbols.map(fetchIntraday));
  let failures = 0;
  results.forEach((result, index) => {
    const symbol = symbols[index];
    if (result.status === "fulfilled") {
      quotes[symbol.quoteID] = result.value;
      quoteCache[symbol.quoteID] = result.value;
      evaluateQuoteAlert(result.value);
    } else {
      failures += 1;
      const cached = quotes[symbol.quoteID];
      if (cached) {
        quotes[symbol.quoteID] = {
          ...cached,
          isStale: true,
          statusMessage: result.reason?.message || "Market data connection failed",
        };
      }
    }
  });
  persistQuotes();
  lastRefresh = new Date().toISOString();
  sourceError = failures === symbols.length
    ? "Market data is temporarily unavailable. The last successful data has been retained."
    : null;
  send("quotes-updated", quotes);
  send("refresh-status", snapshot().status);
  return snapshot();
}

function registerIPC() {
  ipcMain.handle("bootstrap", () => snapshot());
  ipcMain.handle("state:update", (_event, patch) => applyStatePatch(patch || {}));
  ipcMain.handle("stocks:search", (_event, query) => searchStocks(query));
  ipcMain.handle("stocks:add", async (_event, symbol) => {
    if (state.symbols.some((item) => item.quoteID === symbol.quoteID)) {
      return { ok: false, message: "This stock is already on your desktop" };
    }
    applyStatePatch({ symbols: [...state.symbols, symbol] });
    await refreshAll();
    return { ok: true };
  });
  ipcMain.handle("stocks:remove", (_event, quoteID) => {
    applyStatePatch({ symbols: state.symbols.filter((item) => item.quoteID !== quoteID) });
    delete quotes[quoteID];
    delete quoteCache[quoteID];
    delete thresholdStates[quoteID];
    persistQuotes();
    send("quotes-updated", quotes);
    return { ok: true };
  });
  ipcMain.handle("stocks:move", (_event, quoteID, direction) => {
    const symbols = [...state.symbols];
    const from = symbols.findIndex((item) => item.quoteID === quoteID);
    const to = from + Number(direction);
    if (from >= 0 && to >= 0 && to < symbols.length) {
      [symbols[from], symbols[to]] = [symbols[to], symbols[from]];
      applyStatePatch({ symbols });
    }
    return { ok: true };
  });
  ipcMain.handle("quotes:refresh", () => refreshAll());
  ipcMain.handle("alert:preview", (_event, direction) => {
    presentAlert(direction === "falling" ? "falling" : "rising", null, true);
    return { ok: true };
  });
  ipcMain.handle("settings:open", () => {
    openSettings();
    return { ok: true };
  });
  ipcMain.handle("external:open-author", async () => {
    await shell.openExternal("https://github.com/YellowPancake");
    return { ok: true };
  });
  ipcMain.handle("overlay:show", () => {
    overlayWindow?.showInactive();
    return { ok: true };
  });
  ipcMain.on("overlay:drag-start", (_event, point) => {
    if (!overlayWindow || state.clickThrough) return;
    const pointer = { x: Number(point?.x), y: Number(point?.y) };
    if (!Number.isFinite(pointer.x) || !Number.isFinite(pointer.y)) return;
    const [x, y] = overlayWindow.getPosition();
    overlayDragStart = {
      window: { x, y },
      pointer,
    };
  });
  ipcMain.on("overlay:drag-move", (_event, point) => {
    if (!overlayWindow || state.clickThrough || !overlayDragStart) return;
    const pointer = { x: Number(point?.x), y: Number(point?.y) };
    if (!Number.isFinite(pointer.x) || !Number.isFinite(pointer.y)) return;
    const target = overlayDragPosition(
      overlayDragStart.window,
      overlayDragStart.pointer,
      pointer,
    );
    overlayWindow.setPosition(target.x, target.y, false);
  });
  ipcMain.on("overlay:drag-end", () => {
    overlayDragStart = null;
  });
}

const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
} else {
  app.on("second-instance", () => {
    overlayWindow?.showInactive();
  });

  app.whenReady().then(() => {
    app.setAppUserModelId("com.bingge.StockPetEnglish");
    loadData();
    registerIPC();
    createOverlayWindow();
    createTray();
    registerGlobalShortcut();
    resetRefreshTimer();
    refreshAll();
  });

  app.on("before-quit", () => {
    quitting = true;
    globalShortcut.unregisterAll();
  });

  app.on("window-all-closed", () => {
    if (quitting) app.quit();
  });

  app.on("activate", () => {
    if (!overlayWindow) createOverlayWindow();
    overlayWindow?.showInactive();
  });
}
