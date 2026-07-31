"use strict";

const MARKETS = Object.freeze({
  aShare: { label: "A-share", rising: "#ff6673", falling: "#55d69e" },
  hongKong: { label: "HK", rising: "#ff6673", falling: "#55d69e" },
  unitedStates: { label: "US", rising: "#55d69e", falling: "#ff6673" },
});

const INITIAL_SYMBOLS = Object.freeze([
  { code: "600519", name: "Kweichow Moutai", market: "aShare", quoteID: "1.600519" },
  { code: "00700", name: "Tencent Holdings", market: "hongKong", quoteID: "116.00700" },
  { code: "AAPL", name: "Apple", market: "unitedStates", quoteID: "105.AAPL" },
]);

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
    labelOpacity: number(candidate.labelOpacity, 0.92, 0.1, 1),
    backgroundOpacity: number(candidate.backgroundOpacity, 0.16, 0.03, 0.95),
    risingThreshold: number(candidate.risingThreshold, 3, 0.1, 30),
    fallingThreshold: number(candidate.fallingThreshold, 3, 0.1, 30),
    alertBasis: candidate.alertBasis === "targetPrice" ? "targetPrice" : "percentage",
    priceAlertTargets,
    refreshInterval: number(candidate.refreshInterval, 15, 5, 300),
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

module.exports = {
  INITIAL_SYMBOLS,
  MARKETS,
  changePercent,
  colorFor,
  evaluatePriceThreshold,
  evaluateThreshold,
  hasDrawableIntradayData,
  marketForSearchItem,
  parseTencentMinute,
  parseTrend,
  sanitizeState,
  tencentCode,
};
