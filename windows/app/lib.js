"use strict";

const MARKETS = Object.freeze({
  aShare: { label: "A股", rising: "#ff6673", falling: "#55d69e" },
  hongKong: { label: "港股", rising: "#ff6673", falling: "#55d69e" },
  unitedStates: { label: "美股", rising: "#55d69e", falling: "#ff6673" },
});

const INITIAL_SYMBOLS = Object.freeze([
  { code: "600519", name: "贵州茅台", market: "aShare", quoteID: "1.600519" },
  { code: "00700", name: "腾讯控股", market: "hongKong", quoteID: "116.00700" },
  { code: "AAPL", name: "苹果", market: "unitedStates", quoteID: "105.AAPL" },
]);

const OVERLAY_NON_CHART_WIDTH = 430;
const DEFAULT_CHART_WIDTH = 430;
const OVERLAY_ROW_HEIGHT = 82;
const OVERLAY_VERTICAL_CHROME = 40;

function overlayGeometry(
  symbolCount,
  displayScale,
  maximumHeight = Number.POSITIVE_INFINITY,
  chartWidth = DEFAULT_CHART_WIDTH,
) {
  const count = Number.isFinite(Number(symbolCount)) ? Number(symbolCount) : 0;
  const scale = Math.min(1.6, Math.max(0.65, Number(displayScale) || 1));
  const normalizedChartWidth = Math.min(720, Math.max(220, Number(chartWidth) || DEFAULT_CHART_WIDTH));
  const baseWidth = OVERLAY_NON_CHART_WIDTH + normalizedChartWidth;
  const visibleRows = Math.max(1, Math.min(Math.floor(count), 8));
  const baseHeight = Math.max(122, visibleRows * OVERLAY_ROW_HEIGHT + OVERLAY_VERTICAL_CHROME);
  return {
    baseWidth,
    baseHeight,
    width: Math.round(baseWidth * scale),
    height: Math.min(Math.round(baseHeight * scale), Math.max(1, Math.floor(maximumHeight))),
    scale,
  };
}

function overlayDragPosition(windowStart, pointerStart, pointerCurrent) {
  return {
    x: Math.round(windowStart.x + pointerCurrent.x - pointerStart.x),
    y: Math.round(windowStart.y + pointerCurrent.y - pointerStart.y),
  };
}

function colorFor(market, changePercent) {
  const palette = MARKETS[market] || MARKETS.aShare;
  return changePercent >= 0 ? palette.rising : palette.falling;
}

function changePercent(lastPrice, previousClose) {
  if (!Number.isFinite(previousClose) || previousClose <= 0) return 0;
  return ((lastPrice - previousClose) / previousClose) * 100;
}

function marketForSearchItem(item) {
  const classification = String(item.Classify || "").toLowerCase();
  const marketNumber = String(item.MktNum || "");
  if (classification === "astock" || ["0", "1"].includes(marketNumber)) {
    return "aShare";
  }
  if (classification === "hk" || marketNumber === "116") {
    return "hongKong";
  }
  if (classification === "usstock" || ["105", "106", "107"].includes(marketNumber)) {
    return "unitedStates";
  }
  return null;
}

function tencentCode(symbol) {
  if (symbol.market === "hongKong") return `hk${symbol.code}`;
  if (symbol.market === "unitedStates") return `us${symbol.code.toUpperCase()}`;
  if (symbol.code.startsWith("6")) return `sh${symbol.code}`;
  if (/^[489]/.test(symbol.code)) return `bj${symbol.code}`;
  return `sz${symbol.code}`;
}

function tencentRealtimeCode(symbol) {
  if (symbol.market === "hongKong") return `r_hk${symbol.code}`;
  return tencentCode(symbol);
}

function parseTencentRealtime(raw, symbols) {
  const byCode = new Map(symbols.map((symbol) => [tencentRealtimeCode(symbol), symbol]));
  return String(raw || "").split(";").flatMap((row) => {
    const match = row.trim().match(/^v_([^=]+)="?(.*)"?$/s);
    if (!match) return [];
    const symbol = byCode.get(match[1]);
    if (!symbol) return [];
    const fields = match[2].split("~");
    const lastPrice = Number(fields[3]);
    const previousClose = Number(fields[4]);
    const sourceTimestamp = String(fields[30] || "").replaceAll('"', "").trim();
    if (!(lastPrice > 0) || !(previousClose > 0) || !sourceTimestamp) return [];
    return [{ symbol, lastPrice, previousClose, sourceTimestamp }];
  });
}

function isMarketOpen(market, date = new Date()) {
  const timeZone = market === "unitedStates"
    ? "America/New_York"
    : market === "hongKong" ? "Asia/Hong_Kong" : "Asia/Shanghai";
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en-US", {
      timeZone,
      weekday: "short",
      hour: "2-digit",
      minute: "2-digit",
      hourCycle: "h23",
    }).formatToParts(date).map((part) => [part.type, part.value]),
  );
  if (!["Mon", "Tue", "Wed", "Thu", "Fri"].includes(parts.weekday)) return false;
  const minutes = Number(parts.hour) * 60 + Number(parts.minute);
  if (market === "aShare") {
    return (minutes >= 570 && minutes <= 690) || (minutes >= 780 && minutes <= 900);
  }
  if (market === "hongKong") {
    return (minutes >= 570 && minutes <= 720) || (minutes >= 780 && minutes <= 960);
  }
  return minutes >= 570 && minutes <= 960;
}

function failureBackoffSeconds(baseInterval, failureCount) {
  const backoff = [3, 5, 15, 30, 60][Math.min(Math.max(1, failureCount) - 1, 4)];
  return Math.max(Number(baseInterval) || 1, backoff);
}

function isVersionNewer(candidate, current) {
  const normalize = (value) => String(value || "0")
    .trim().replace(/^[vV]/, "").split("-")[0]
    .split(".").map((part) => Number(part) || 0);
  const left = normalize(candidate);
  const right = normalize(current);
  for (let index = 0; index < Math.max(left.length, right.length); index += 1) {
    const difference = (left[index] || 0) - (right[index] || 0);
    if (difference) return difference > 0;
  }
  return false;
}

function parseTencentMinute(raw, date) {
  const values = String(raw).trim().split(/\s+/);
  const price = Number(values[1]);
  if (values.length < 2 || values[0].length !== 4 || !(price > 0)) return null;
  const normalizedDate = /^\d{8}$/.test(date)
    ? `${date.slice(0, 4)}-${date.slice(4, 6)}-${date.slice(6, 8)}`
    : String(date || "").slice(0, 10).replaceAll("/", "-");
  return {
    time: `${normalizedDate} ${values[0].slice(0, 2)}:${values[0].slice(2)}`,
    price,
  };
}

function parseTrend(raw) {
  const values = String(raw).split(",");
  const open = Number(values[1]);
  const close = Number(values[2]);
  const high = Number(values[3]);
  const low = Number(values[4]);
  if (values.length < 5 || !(close > 0)) return null;
  return { time: values[0], open, price: close, high, low };
}

function hasDrawableIntradayData(points) {
  return Array.isArray(points) && points.length >= 2;
}

function evaluateThreshold(previousState, percent, risingThreshold, fallingThreshold, hysteresis = 0.15) {
  let state = previousState || "armed";
  let direction = null;
  if (percent >= risingThreshold && state !== "risingTriggered") {
    state = "risingTriggered";
    direction = "rising";
  } else if (percent <= -fallingThreshold && state !== "fallingTriggered") {
    state = "fallingTriggered";
    direction = "falling";
  } else if (
    percent < risingThreshold - hysteresis &&
    percent > -fallingThreshold + hysteresis
  ) {
    state = "armed";
  }
  return { state, direction };
}

function evaluatePriceThreshold(
  previousState,
  price,
  risingTarget,
  fallingTarget,
  hysteresisRatio = 0.0015,
) {
  let state = previousState || "armed";
  let direction = null;
  if (risingTarget > 0 && price >= risingTarget && state !== "risingTriggered") {
    state = "risingTriggered";
    direction = "rising";
  } else if (fallingTarget > 0 && price <= fallingTarget && state !== "fallingTriggered") {
    state = "fallingTriggered";
    direction = "falling";
  } else {
    const belowRisingRearm = !(risingTarget > 0) || price < risingTarget * (1 - hysteresisRatio);
    const aboveFallingRearm = !(fallingTarget > 0) || price > fallingTarget * (1 + hysteresisRatio);
    if (belowRisingRearm && aboveFallingRearm) state = "armed";
  }
  return { state, direction };
}

function sanitizeState(candidate = {}) {
  const symbols = Array.isArray(candidate.symbols)
    ? candidate.symbols
        .filter((item) => item && item.code && item.name && MARKETS[item.market] && item.quoteID)
    : [...INITIAL_SYMBOLS];
  const number = (value, fallback, min, max) => {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? Math.min(max, Math.max(min, parsed)) : fallback;
  };
  const symbolIDs = new Set(symbols.map((symbol) => symbol.quoteID));
  const priceAlertTargets = Object.fromEntries(
    Object.entries(candidate.priceAlertTargets || {})
      .filter(([quoteID, targets]) => symbolIDs.has(quoteID) && targets)
      .map(([quoteID, targets]) => [
        quoteID,
        {
          risingPrice: number(targets.risingPrice, 0, 0, 100000000),
          fallingPrice: number(targets.fallingPrice, 0, 0, 100000000),
        },
      ])
      .filter(([, targets]) => targets.risingPrice > 0 || targets.fallingPrice > 0),
  );
  return {
    symbols,
    lineOpacity: number(candidate.lineOpacity, 0.92, 0.1, 1),
    chartWidth: number(candidate.chartWidth, 430, 220, 720),
    labelOpacity: number(candidate.labelOpacity, 0.92, 0.1, 1),
    fontScale: number(candidate.fontScale, 1, 0.75, 1.5),
    changeDisplayMode: candidate.changeDisplayMode === "amount" ? "amount" : "percentage",
    showStockMeta: Boolean(candidate.showStockMeta),
    backgroundOpacity: number(candidate.backgroundOpacity, 0.16, 0, 0.95),
    risingThreshold: number(candidate.risingThreshold, 3, 0.1, 30),
    fallingThreshold: number(candidate.fallingThreshold, 3, 0.1, 30),
    alertBasis: candidate.alertBasis === "targetPrice" ? "targetPrice" : "percentage",
    priceAlertTargets,
    refreshInterval: number(candidate.refreshInterval, 15, 1, 300),
    clickThrough: Boolean(candidate.clickThrough),
    alwaysOnTop: candidate.alwaysOnTop !== false,
    displayScale: number(candidate.displayScale, 1, 0.65, 1.6),
    bullSoundEnabled: candidate.bullSoundEnabled !== false,
    bearSoundEnabled: candidate.bearSoundEnabled !== false,
    alertsEnabled: candidate.alertsEnabled !== false,
    alertOpacity: number(candidate.alertOpacity, 0.94, 0.2, 1),
    shortcutEnabled: candidate.shortcutEnabled !== false,
    shortcutModifier: [
      "Ctrl+Alt",
      "Ctrl+Shift",
      "Alt+Shift",
      "Ctrl+Alt+Shift",
    ].includes(candidate.shortcutModifier)
      ? candidate.shortcutModifier
      : "Ctrl+Alt",
    shortcutKey: ["S", "P", "H", "K", "D", "F", "Space"].includes(candidate.shortcutKey)
      ? candidate.shortcutKey
      : "S",
  };
}

function releaseDigest(notes, assetName) {
  const escapedName = assetName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = String(notes || "").match(
    new RegExp(`^SHA256\\s*\\(${escapedName}\\)\\s*:\\s*([0-9a-f]{64})\\s*$`, "im"),
  );
  return match ? `sha256:${match[1].toLowerCase()}` : null;
}

function releaseParts(attachments, assetName) {
  const exact = attachments.find((item) => item.name === assetName && item.browser_download_url);
  if (exact) return [{ url: exact.browser_download_url, size: Number(exact.size) || 0 }];
  const prefix = `${assetName}.part`;
  return attachments
    .filter((item) => item.name?.startsWith(prefix) && item.browser_download_url)
    .map((item) => ({
      index: Number(item.name.slice(prefix.length)),
      url: item.browser_download_url,
      size: Number(item.size) || 0,
    }))
    .filter((item) => Number.isInteger(item.index) && item.index > 0)
    .sort((left, right) => left.index - right.index)
    .map(({ url, size }) => ({ url, size }));
}

module.exports = {
  INITIAL_SYMBOLS,
  MARKETS,
  changePercent,
  colorFor,
  evaluatePriceThreshold,
  evaluateThreshold,
  failureBackoffSeconds,
  hasDrawableIntradayData,
  marketForSearchItem,
  isMarketOpen,
  isVersionNewer,
  overlayDragPosition,
  overlayGeometry,
  parseTencentMinute,
  parseTencentRealtime,
  parseTrend,
  releaseDigest,
  releaseParts,
  sanitizeState,
  tencentCode,
  tencentRealtimeCode,
};
