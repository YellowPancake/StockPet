"use strict";

const {
  app,
  BrowserWindow,
  globalShortcut,
  ipcMain,
  Menu,
  nativeImage,
  net,
  screen,
  shell,
  Tray,
} = require("electron");
const fs = require("node:fs");
const path = require("node:path");
const { createHash } = require("node:crypto");
const { Readable, Transform } = require("node:stream");
const { pipeline } = require("node:stream/promises");
const {
  changePercent,
  evaluatePriceThreshold,
  evaluateThreshold,
  failureBackoffSeconds,
  isMarketOpen,
  isVersionNewer,
  overlayDragPosition,
  overlayGeometry,
  sanitizeState,
} = require("./lib");
const { fetchIntraday, fetchLatestQuotes, searchStocks } = require("./quote-service");

let overlayWindow = null;
let settingsWindow = null;
let tray = null;
let latestRefreshTimer = null;
let intradayRefreshTimer = null;
let latestRefreshFailures = 0;
let latestQuoteTimestamps = {};
let intradayRefreshPromise = null;
let latestRefreshPromise = null;
let refreshGeneration = 0;
let state = sanitizeState();
let quotes = {};
let quoteCache = {};
let thresholdStates = {};
let lastRefresh = null;
let sourceError = null;
let quitting = false;
let overlayDragStart = null;
let availableUpdate = null;

const UPDATE_ASSET_NAME = "StockPet-Windows-x64-Chinese.zip";
const RELEASES_API = "https://api.github.com/repos/YellowPancake/StockPet/releases/latest";

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

async function checkForSoftwareUpdate() {
  const response = await net.fetch(RELEASES_API, {
    cache: "no-store",
    headers: {
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
      "User-Agent": `StockPet/${app.getVersion()}`,
    },
  });
  if (!response.ok) throw new Error("检查更新失败，请稍后重试");
  const release = await response.json();
  const version = String(release.tag_name || "").replace(/^[vV]/, "").split("-")[0];
  if (!isVersionNewer(version, app.getVersion())) {
    availableUpdate = null;
    return { status: "upToDate", currentVersion: app.getVersion() };
  }
  const asset = (release.assets || []).find((item) => item.name === UPDATE_ASSET_NAME);
  if (!asset?.browser_download_url || !String(asset.digest || "").startsWith("sha256:")) {
    throw new Error("新版本缺少适用于当前系统的安装包");
  }
  availableUpdate = {
    version,
    notes: release.body || "",
    releasePageURL: release.html_url,
    assetName: asset.name,
    assetURL: asset.browser_download_url,
    digest: String(asset.digest).toLowerCase(),
  };
  return { status: "available", update: availableUpdate };
}

function availableDownloadPath(update) {
  const extension = path.extname(update.assetName);
  const baseName = path.basename(update.assetName, extension);
  const directory = app.getPath("downloads");
  let candidate = path.join(directory, `${baseName}-v${update.version}${extension}`);
  let suffix = 2;
  while (fs.existsSync(candidate)) {
    candidate = path.join(directory, `${baseName}-v${update.version}-${suffix}${extension}`);
    suffix += 1;
  }
  return candidate;
}

async function downloadSoftwareUpdate() {
  if (!availableUpdate) await checkForSoftwareUpdate();
  if (!availableUpdate) return { status: "upToDate" };
  const update = availableUpdate;
  const destination = availableDownloadPath(update);
  const temporary = `${destination}.download-${process.pid}-${Date.now()}`;
  const response = await net.fetch(update.assetURL, {
    cache: "no-store",
    headers: {
      Accept: "application/octet-stream",
      "User-Agent": `StockPet/${app.getVersion()}`,
    },
  });
  if (!response.ok || !response.body) throw new Error("更新包下载失败，请稍后重试");

  const total = Number(response.headers.get("content-length")) || 0;
  let received = 0;
  let lastProgressAt = 0;
  const hash = createHash("sha256");
  const verifier = new Transform({
    transform(chunk, _encoding, callback) {
      hash.update(chunk);
      received += chunk.length;
      const now = Date.now();
      if (now - lastProgressAt >= 200 || received === total) {
        send("update-download-progress", { received, total });
        lastProgressAt = now;
      }
      callback(null, chunk);
    },
  });
  try {
    await pipeline(Readable.fromWeb(response.body), verifier, fs.createWriteStream(temporary));
    const actualDigest = `sha256:${hash.digest("hex")}`;
    if (actualDigest !== update.digest) throw new Error("更新包校验失败，已停止下载");
    await fs.promises.rename(temporary, destination);
  } catch (error) {
    await fs.promises.unlink(temporary).catch(() => {});
    throw error;
  }
  shell.showItemInFolder(destination);
  return { status: "downloaded", filePath: destination };
}

function snapshot() {
  return {
    state,
    quotes,
    status: {
      lastRefresh,
      sourceError,
      source: "腾讯秒级报价 · 腾讯分时 · 东方财富备用",
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
  const geometry = overlayGeometry(
    state.symbols.length,
    state.displayScale,
    maximumHeight,
    state.chartWidth,
  );
  overlayWindow.webContents.setZoomFactor(1);
  // Keep the native window and the rendered board on the same deterministic size.
  // Animated resizing can briefly expose the old viewport to the renderer and make
  // the board appear to stay fixed while its contents scale.
  overlayWindow.setSize(geometry.width, geometry.height, false);
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
    minWidth: 400,
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
    title: "Stock Pet 设置",
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
      label: overlayWindow?.isVisible() ? "隐藏桌宠" : "显示桌宠",
      click: toggleOverlay,
    },
    { label: "立即刷新", click: () => refreshAll() },
    {
      label: "锁定并穿透鼠标",
      type: "checkbox",
      checked: state.clickThrough,
      click: (item) => applyStatePatch({ clickThrough: item.checked }),
    },
    {
      label: "始终置顶",
      type: "checkbox",
      checked: state.alwaysOnTop,
      click: (item) => applyStatePatch({ alwaysOnTop: item.checked }),
    },
    { type: "separator" },
    { label: "设置…", click: openSettings },
    { type: "separator" },
    {
      label: "退出 Stock Pet",
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
  if (latestRefreshTimer) clearTimeout(latestRefreshTimer);
  if (intradayRefreshTimer) clearTimeout(intradayRefreshTimer);
  latestRefreshFailures = 0;
  const generation = ++refreshGeneration;
  latestRefreshTimer = setTimeout(
    () => runLatestRefreshLoop(generation),
    state.refreshInterval * 1000,
  );
  intradayRefreshTimer = setTimeout(
    () => runIntradayRefreshLoop(generation),
    intradayDelaySeconds() * 1000,
  );
}

function hasOpenMarket() {
  const now = new Date();
  return state.symbols.some((symbol) => isMarketOpen(symbol.market, now));
}

function intradayDelaySeconds() {
  return hasOpenMarket() ? Math.max(15, state.refreshInterval) : 60;
}

async function runLatestRefreshLoop(generation) {
  if (generation !== refreshGeneration) return;
  latestRefreshTimer = null;
  const now = new Date();
  const activeSymbols = state.symbols.filter((symbol) => isMarketOpen(symbol.market, now));
  let delay = 30;
  if (activeSymbols.length) {
    const succeeded = await refreshLatest(activeSymbols);
    latestRefreshFailures = succeeded ? 0 : Math.min(latestRefreshFailures + 1, 5);
    delay = latestRefreshFailures
      ? failureBackoffSeconds(state.refreshInterval, latestRefreshFailures)
      : state.refreshInterval;
  }
  if (!quitting && generation === refreshGeneration) {
    latestRefreshTimer = setTimeout(
      () => runLatestRefreshLoop(generation),
      delay * 1000,
    );
  }
}

async function runIntradayRefreshLoop(generation) {
  if (generation !== refreshGeneration) return;
  intradayRefreshTimer = null;
  await refreshAll();
  if (!quitting && generation === refreshGeneration) {
    intradayRefreshTimer = setTimeout(
      () => runIntradayRefreshLoop(generation),
      intradayDelaySeconds() * 1000,
    );
  }
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
    name: "预览",
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
  if (intradayRefreshPromise) return intradayRefreshPromise;
  intradayRefreshPromise = performIntradayRefresh().finally(() => {
    intradayRefreshPromise = null;
  });
  return intradayRefreshPromise;
}

async function performIntradayRefresh() {
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
      const existing = quotes[symbol.quoteID];
      const sourceTimestamp = latestQuoteTimestamps[symbol.quoteID];
      const merged = existing && sourceTimestamp
        ? {
            ...result.value,
            lastPrice: existing.lastPrice,
            changePercent: changePercent(existing.lastPrice, result.value.previousClose),
            updatedAt: existing.updatedAt,
            sourceTimestamp,
          }
        : result.value;
      quotes[symbol.quoteID] = merged;
      quoteCache[symbol.quoteID] = merged;
      evaluateQuoteAlert(merged);
    } else {
      failures += 1;
      const cached = quotes[symbol.quoteID];
      if (cached) {
        quotes[symbol.quoteID] = {
          ...cached,
          isStale: true,
          statusMessage: result.reason?.message || "行情连接失败",
        };
      }
    }
  });
  persistQuotes();
  lastRefresh = new Date().toISOString();
  sourceError = failures === symbols.length ? "行情连接暂不可用，已保留上次成功数据" : null;
  send("quotes-updated", quotes);
  send("refresh-status", snapshot().status);
  return snapshot();
}

async function refreshLatest(symbols) {
  if (latestRefreshPromise) return latestRefreshPromise;
  latestRefreshPromise = performLatestRefresh(symbols).finally(() => {
    latestRefreshPromise = null;
  });
  return latestRefreshPromise;
}

async function performLatestRefresh(symbols) {
  try {
    const updates = await fetchLatestQuotes(symbols);
    let applied = 0;
    for (const update of updates) {
      const id = update.symbol.quoteID;
      if (latestQuoteTimestamps[id]
          && update.sourceTimestamp <= latestQuoteTimestamps[id]) continue;
      latestQuoteTimestamps[id] = update.sourceTimestamp;
      const existing = quotes[id];
      const quote = {
        symbol: update.symbol,
        points: existing?.points || [],
        dayOpen: existing?.dayOpen || update.lastPrice,
        previousClose: update.previousClose,
        lastPrice: update.lastPrice,
        changePercent: changePercent(update.lastPrice, update.previousClose),
        updatedAt: update.sourceTimestamp,
        sourceTimestamp: update.sourceTimestamp,
        isStale: false,
        source: "腾讯秒级报价",
      };
      quotes[id] = quote;
      quoteCache[id] = quote;
      evaluateQuoteAlert(quote);
      applied += 1;
    }
    if (applied) {
      lastRefresh = new Date().toISOString();
      sourceError = null;
      send("quotes-updated", quotes);
      send("refresh-status", snapshot().status);
    }
    return updates.length > 0;
  } catch {
    if (!Object.keys(quotes).length) {
      sourceError = "实时价格暂时不可用，分时曲线仍会继续刷新";
      send("refresh-status", snapshot().status);
    }
    return false;
  }
}

function registerIPC() {
  ipcMain.handle("bootstrap", () => snapshot());
  ipcMain.handle("state:update", (_event, patch) => applyStatePatch(patch || {}));
  ipcMain.handle("stocks:search", (_event, query) => searchStocks(query));
  ipcMain.handle("stocks:add", async (_event, symbol) => {
    if (state.symbols.some((item) => item.quoteID === symbol.quoteID)) {
      return { ok: false, message: "这只股票已经在桌面上了" };
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
    delete latestQuoteTimestamps[quoteID];
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
  ipcMain.handle("update:check", () => checkForSoftwareUpdate());
  ipcMain.handle("update:download", () => downloadSoftwareUpdate());
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
    app.setAppUserModelId("com.bingge.StockPet");
    loadData();
    registerIPC();
    createOverlayWindow();
    createTray();
    registerGlobalShortcut();
    refreshAll().finally(resetRefreshTimer);
  });

  app.on("before-quit", () => {
    quitting = true;
    if (latestRefreshTimer) clearTimeout(latestRefreshTimer);
    if (intradayRefreshTimer) clearTimeout(intradayRefreshTimer);
    refreshGeneration += 1;
    persistQuotes();
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
