"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
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
  sanitizeState,
  tencentCode,
  tencentRealtimeCode,
} = require("../app/lib");

test("overlay geometry scales the whole board linearly", () => {
  const normal = overlayGeometry(3, 1, 2000);
  const smaller = overlayGeometry(3, 0.65, 2000);
  const larger = overlayGeometry(3, 1.6, 2000);
  assert.deepEqual(normal, {
    baseWidth: 860,
    baseHeight: 286,
    width: 860,
    height: 286,
    scale: 1,
  });
  assert.equal(smaller.width, Math.round(normal.width * 0.65));
  assert.equal(smaller.height, Math.round(normal.height * 0.65));
  assert.equal(larger.width, Math.round(normal.width * 1.6));
  assert.equal(larger.height, Math.round(normal.height * 1.6));
  assert.equal(overlayGeometry(3, 1, 2000, 620).baseWidth, 1050);
});

test("overlay dragging uses the original window position without accumulating movement", () => {
  const windowStart = { x: 100, y: 200 };
  const pointerStart = { x: 500, y: 400 };
  const pointerCurrent = { x: 545, y: 372 };
  const expected = { x: 145, y: 172 };
  assert.deepEqual(overlayDragPosition(windowStart, pointerStart, pointerCurrent), expected);
  assert.deepEqual(overlayDragPosition(windowStart, pointerStart, pointerCurrent), expected);
});

test("A/H and US markets use opposite rise/fall colors", () => {
  assert.equal(colorFor("aShare", 1), "#ff6673");
  assert.equal(colorFor("hongKong", -1), "#55d69e");
  assert.equal(colorFor("unitedStates", 1), "#55d69e");
  assert.equal(colorFor("unitedStates", -1), "#ff6673");
});

test("Tencent symbols are mapped for A/H/US markets", () => {
  assert.equal(tencentCode({ code: "600519", market: "aShare" }), "sh600519");
  assert.equal(tencentCode({ code: "300308", market: "aShare" }), "sz300308");
  assert.equal(tencentCode({ code: "00700", market: "hongKong" }), "hk00700");
  assert.equal(tencentCode({ code: "aapl", market: "unitedStates" }), "usAAPL");
  assert.equal(tencentRealtimeCode({ code: "00700", market: "hongKong" }), "r_hk00700");
});

test("Tencent batch realtime quotes are parsed", () => {
  const symbol = { code: "600519", name: "贵州茅台", market: "aShare", quoteID: "1.600519" };
  const fields = Array(31).fill("");
  Object.assign(fields, { 0: "1", 1: "Kweichow Moutai", 2: "600519", 3: "1355.70", 4: "1350", 30: "20260803145240" });
  const updates = parseTencentRealtime(`v_sh600519="${fields.join("~")}";`, [symbol]);
  assert.equal(updates.length, 1);
  assert.equal(updates[0].lastPrice, 1355.7);
  assert.equal(updates[0].sourceTimestamp, "20260803145240");
});

test("market sessions and failure backoff protect fast refresh", () => {
  assert.equal(isMarketOpen("aShare", new Date("2026-08-03T02:00:00Z")), true);
  assert.equal(isMarketOpen("aShare", new Date("2026-08-03T04:00:00Z")), false);
  assert.equal(isMarketOpen("unitedStates", new Date("2026-08-03T15:00:00Z")), true);
  assert.equal(failureBackoffSeconds(1, 1), 3);
  assert.equal(failureBackoffSeconds(1, 4), 30);
});

test("semantic versions detect newer releases", () => {
  assert.equal(isVersionNewer("0.4.0", "0.3.0"), true);
  assert.equal(isVersionNewer("v1.0.0", "0.9.9"), true);
  assert.equal(isVersionNewer("0.4.0", "0.4.0"), false);
});

test("market search results only keep A/H/US classifications", () => {
  assert.equal(marketForSearchItem({ Classify: "AStock", MktNum: "1" }), "aShare");
  assert.equal(marketForSearchItem({ Classify: "HK", MktNum: "116" }), "hongKong");
  assert.equal(marketForSearchItem({ Classify: "USStock", MktNum: "105" }), "unitedStates");
  assert.equal(marketForSearchItem({ Classify: "Fund", MktNum: "90" }), null);
});

test("minute formats are parsed into chart points", () => {
  assert.deepEqual(parseTencentMinute("0930 12.34 100", "20260730"), {
    time: "2026-07-30 09:30",
    price: 12.34,
  });
  assert.equal(parseTencentMinute("bad", "20260730"), null);
  assert.deepEqual(parseTrend("2026-07-30 09:30,12,12.5,13,11.8,0"), {
    time: "2026-07-30 09:30",
    open: 12,
    price: 12.5,
    high: 13,
    low: 11.8,
  });
});

test("a single Tencent point is not enough to draw an intraday chart", () => {
  assert.equal(hasDrawableIntradayData([]), false);
  assert.equal(hasDrawableIntradayData([{ price: 333.43 }]), false);
  assert.equal(hasDrawableIntradayData([{ price: 333.43 }, { price: 333.5 }]), true);
});

test("threshold gate fires once and rearms after hysteresis", () => {
  let result = evaluateThreshold("armed", 3.1, 3, 3);
  assert.equal(result.direction, "rising");
  result = evaluateThreshold(result.state, 3.2, 3, 3);
  assert.equal(result.direction, null);
  result = evaluateThreshold(result.state, 2.7, 3, 3);
  assert.equal(result.state, "armed");
  result = evaluateThreshold(result.state, -3.2, 3, 3);
  assert.equal(result.direction, "falling");
});

test("target-price gate fires and rearms after a 0.15% move inside", () => {
  let result = evaluatePriceThreshold("armed", 103, 103, 97);
  assert.equal(result.direction, "rising");
  result = evaluatePriceThreshold(result.state, 102.9, 103, 97);
  assert.equal(result.direction, null);
  result = evaluatePriceThreshold(result.state, 102.8, 103, 97);
  assert.equal(result.state, "armed");
  result = evaluatePriceThreshold(result.state, 103.1, 103, 97);
  assert.equal(result.direction, "rising");
  result = evaluatePriceThreshold(result.state, 96.9, 103, 97);
  assert.equal(result.direction, "falling");
});

test("persisted settings are clamped and a deliberately empty list stays empty", () => {
  const state = sanitizeState({
    symbols: [],
    displayScale: 9,
    lineOpacity: -2,
    chartWidth: 999,
    fontScale: 99,
    backgroundOpacity: 0,
    refreshInterval: 1,
  });
  assert.deepEqual(state.symbols, []);
  assert.equal(state.displayScale, 1.6);
  assert.equal(state.lineOpacity, 0.1);
  assert.equal(state.chartWidth, 720);
  assert.equal(state.fontScale, 1.5);
  assert.equal(state.showStockMeta, false);
  assert.equal(state.backgroundOpacity, 0);
  assert.equal(state.refreshInterval, 1);
});

test("stock code and market are hidden by default and can be enabled", () => {
  assert.equal(sanitizeState().showStockMeta, false);
  assert.equal(sanitizeState({ showStockMeta: true }).showStockMeta, true);
});

test("persisted watchlist is not capped at ten stocks", () => {
  const symbols = Array.from({ length: 12 }, (_value, index) => ({
    code: `TEST${index}`,
    name: `测试${index}`,
    market: "unitedStates",
    quoteID: `105.TEST${index}`,
  }));
  const state = sanitizeState({ symbols });
  assert.equal(state.symbols.length, 12);
});

test("target-price settings keep only valid watchlist rules", () => {
  const symbol = {
    code: "AAPL",
    name: "苹果",
    market: "unitedStates",
    quoteID: "105.AAPL",
  };
  const state = sanitizeState({
    symbols: [symbol],
    alertBasis: "targetPrice",
    priceAlertTargets: {
      "105.AAPL": { risingPrice: 250, fallingPrice: 210 },
      "105.GONE": { risingPrice: 10, fallingPrice: 5 },
    },
  });
  assert.equal(state.alertBasis, "targetPrice");
  assert.deepEqual(state.priceAlertTargets, {
    "105.AAPL": { risingPrice: 250, fallingPrice: 210 },
  });
});
