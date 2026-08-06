"use strict";

const {
  app,
  BrowserWindow,
  globalShortcut,
  ipcMain,
  Menu,
  nativeImage,
  net,
  powerMonitor,
  screen,
  shell,
  Tray,
} = require("electron");
const fs = require("node:fs");
const path = require("node:path");
const { createHash } = require("node:crypto");
const {
  changePercent,
  evaluatePriceThreshold,
  evaluateThreshold,
  failureBackoffSeconds,
  isMarketOpen,
  isVersionNewer,
  overlayDragPosition,
  overlayGeometry,
  releaseDigest,
  releaseParts,
  sanitizeState,
  shouldScheduleShow,
} = require("./lib");
const { fetchIntraday, fetchLatestQuotes, searchStocks } = require("./quote-service");

// Keep the English edition's defaults and preferences independent from the
// Chinese edition, even when both are installed on the same Windows account.
app.setPath("userData", path.join(app.getPath("appData"), "StockPet-English"));

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
let registeredShortcut = null;
let shortcutHealthTimer = null;
let visibilityScheduleTimer = null;

const UPDATE_ASSET_NAME = "StockPet-Windows-x64-English.zip";
const GITHUB_RELEASES_API = "https://api.github.com/repos/YellowPancake/StockPet/releases/latest";
const GITEE_RELEASES_API = "https://gitee.com/api/v5/repos/YBigPie/StockPet/releases/latest";

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

async function fetchUpdateJSON(url, headers = {}) {
  const response = await net.fetch(url, {
    cache: "no-store",
    headers: {
      Accept: "application/json",
      "User-Agent": `StockPet/${app.getVersion()}`,
      ...headers,
    },
  });
  if (!response.ok) throw new Error("Unable to check for updates. Please try again later.");
  return response.json();
}

async function githubUpdateCandidate() {
  const release = await fetchUpdateJSON(GITHUB_RELEASES_API, {
    Accept: "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
  });
  const version = String(release.tag_name || "").replace(/^[vV]/, "").split("-")[0];
  const asset = (release.assets || []).find((item) => item.name === UPDATE_ASSET_NAME);
  if (!asset?.browser_download_url || !String(asset.digest || "").startsWith("sha256:")) {
    throw new Error("The new release does not include a package for this system.");
  }
  return {
    version,
    notes: release.body || "",
    download: {
      route: "routeOne",
      assetName: asset.name,
      parts: [{ url: asset.browser_download_url, size: Number(asset.size) || 0 }],
      digest: String(asset.digest).toLowerCase(),
    },
  };
}

async function giteeUpdateCandidate() {
  const release = await fetchUpdateJSON(GITEE_RELEASES_API);
  const attachments = await fetchUpdateJSON(
    `https://gitee.com/api/v5/repos/YBigPie/StockPet/releases/${release.id}/attach_files?per_page=100`,
  );
  const parts = releaseParts(attachments, UPDATE_ASSET_NAME);
  const digest = releaseDigest(release.body, UPDATE_ASSET_NAME);
  if (!parts.length || !digest) {
    throw new Error("The new release does not include a package for this system.");
  }
  return {
    version: String(release.tag_name || "").replace(/^[vV]/, "").split("-")[0],
    notes: release.body || "",
    download: {
      route: "routeTwo",
      assetName: UPDATE_ASSET_NAME,
      parts,
      digest,
    },
  };
}

async function checkForSoftwareUpdate() {
  const results = await Promise.allSettled([githubUpdateCandidate(), giteeUpdateCandidate()]);
  const candidates = results.filter((item) => item.status === "fulfilled").map((item) => item.value);
  if (!candidates.length) throw new Error("Unable to check for updates. Please try again later.");
  const newer = candidates.filter((item) => isVersionNewer(item.version, app.getVersion()));
  if (!newer.length) {
    availableUpdate = null;
    return { status: "upToDate", currentVersion: app.getVersion() };
  }
  const latest = newer.reduce((selected, item) => (
    isVersionNewer(item.version, selected.version) ? item : selected
  ));
  const matching = newer.filter((item) => item.version === latest.version);
  availableUpdate = {
    version: latest.version,
    notes: matching.find((item) => item.notes)?.notes || "",
    downloads: Object.fromEntries(matching.map((item) => [item.download.route, item.download])),
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

async function downloadSoftwareUpdate(route) {
  if (!availableUpdate) await checkForSoftwareUpdate();
  if (!availableUpdate) return { status: "upToDate" };
  const update = availableUpdate;
  const download = update.downloads?.[route];
  if (!download) {
    throw new Error("That download route is temporarily unavailable. Please try the other route.");
  }
  const destination = availableDownloadPath({ ...update, assetName: download.assetName });
  const temporary = `${destination}.download-${process.pid}-${Date.now()}`;
  const total = download.parts.reduce((sum, part) => sum + (Number(part.size) || 0), 0);
  let received = 0;
  let lastProgressAt = 0;
  const hash = createHash("sha256");
  try {
    await fs.promises.writeFile(temporary, Buffer.alloc(0));
    for (const part of download.parts) {
      const response = await net.fetch(part.url, {
        cache: "no-store",
        headers: {
          Accept: "application/octet-stream",
          "User-Agent": `StockPet/${app.getVersion()}`,
        },
      });
      if (!response.ok) {
        throw new Error("Unable to download the update. Please try again later.");
      }
      const chunk = Buffer.from(await response.arrayBuffer());
      hash.update(chunk);
      received += chunk.length;
      await fs.promises.appendFile(temporary, chunk);
      const now = Date.now();
      if (now - lastProgressAt >= 200 || received >= total) {
        send("update-download-progress", { received, total });
        lastProgressAt = now;
      }
    }
    const actualDigest = `sha256:${hash.digest("hex")}`;
    if (actualDigest !== download.digest) {
      throw new Error("Update verification failed, so the download was stopped.");
    }
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
      source: "Tencent fast quotes · Tencent intraday · Eastmoney fallback",
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

function setOverlayVisible(visible) {
  if (!overlayWindow) return;
  visible ? overlayWindow.showInactive() : overlayWindow.hide();
  rebuildTrayMenu();
}

function resetVisibilitySchedule(reconcileNow = true) {
  if (visibilityScheduleTimer) clearTimeout(visibilityScheduleTimer);
  visibilityScheduleTimer = null;
  if (!state.visibilityScheduleEnabled || state.scheduledShowTime === state.scheduledHideTime) return;

  const now = new Date();
  const nowMinutes = now.getHours() * 60 + now.getMinutes();
  if (reconcileNow) {
    const visible = shouldScheduleShow(nowMinutes, state.scheduledShowTime, state.scheduledHideTime);
    if (visible !== null) setOverlayVisible(visible);
  }
  const nextDate = (clock) => {
    const [hour, minute] = clock.split(":").map(Number);
    const result = new Date(now);
    result.setHours(hour, minute, 0, 0);
    if (result <= now) result.setDate(result.getDate() + 1);
    return result;
  };
  const next = [nextDate(state.scheduledShowTime), nextDate(state.scheduledHideTime)]
    .sort((left, right) => left - right)[0];
  visibilityScheduleTimer = setTimeout(() => resetVisibilitySchedule(true), next - now);
}

function configuredShortcut() {
  return `${state.shortcutModifier}+${state.shortcutKey}`;
}

function registerGlobalShortcut() {
  globalShortcut.unregisterAll();
  registeredShortcut = null;
  if (!state.shortcutEnabled) return true;
  const accelerator = configuredShortcut();
  const succeeded = globalShortcut.register(accelerator, () => {
    setImmediate(toggleOverlay);
  });
  if (succeeded && globalShortcut.isRegistered(accelerator)) {
    registeredShortcut = accelerator;
    return true;
  }
  return false;
}

function ensureGlobalShortcutRegistered() {
  if (!state.shortcutEnabled || quitting || !app.isReady()) return;
  const accelerator = configuredShortcut();
  if (registeredShortcut === accelerator && globalShortcut.isRegistered(accelerator)) return;
  registerGlobalShortcut();
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
    if (state.visibilityScheduleEnabled) resetVisibilitySchedule(true);
    else overlayWindow.showInactive();
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
  const scheduleChanged = (
    patch.visibilityScheduleEnabled !== undefined ||
    patch.scheduledShowTime !== undefined ||
    patch.scheduledHideTime !== undefined
  );
  state = sanitizeState({ ...state, ...patch });
  thresholdStates = {};
  persistState();
  notifyStateChanged();
  if (!state.alertsEnabled) send("alert-dismiss", null);
  if (shortcutChanged) registerGlobalShortcut();
  if (scheduleChanged) resetVisibilitySchedule(true);
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
        source: update.source === "eastmoney" ? "Eastmoney index quotes" : "Tencent fast quote",
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
      sourceError = "Fast quotes are temporarily unavailable; intraday charts will keep refreshing";
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
  ipcMain.handle("update:download", (_event, route) => downloadSoftwareUpdate(route));
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
    resetVisibilitySchedule(true);
    shortcutHealthTimer = setInterval(ensureGlobalShortcutRegistered, 3000);
    app.on("browser-window-blur", () => setImmediate(ensureGlobalShortcutRegistered));
    powerMonitor.on("resume", () => {
      ensureGlobalShortcutRegistered();
      resetVisibilitySchedule(true);
    });
    powerMonitor.on("unlock-screen", () => {
      ensureGlobalShortcutRegistered();
      resetVisibilitySchedule(true);
    });
    refreshAll().finally(resetRefreshTimer);
  });

  app.on("before-quit", () => {
    quitting = true;
    if (latestRefreshTimer) clearTimeout(latestRefreshTimer);
    if (intradayRefreshTimer) clearTimeout(intradayRefreshTimer);
    if (shortcutHealthTimer) clearInterval(shortcutHealthTimer);
    if (visibilityScheduleTimer) clearTimeout(visibilityScheduleTimer);
    refreshGeneration += 1;
    persistQuotes();
    globalShortcut.unregisterAll();
    registeredShortcut = null;
  });

  app.on("window-all-closed", () => {
    if (quitting) app.quit();
  });

  app.on("activate", () => {
    if (!overlayWindow) createOverlayWindow();
    overlayWindow?.showInactive();
  });
}
