"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  colorFor,
  evaluatePriceThreshold,
  evaluateThreshold,
  marketForSearchItem,
  parseTencentMinute,
  parseTrend,
  sanitizeState,
  tencentCode,
} = require("../app/lib");

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
    refreshInterval: 1,
  });
  assert.deepEqual(state.symbols, []);
  assert.equal(state.displayScale, 1.6);
  assert.equal(state.lineOpacity, 0.1);
  assert.equal(state.refreshInterval, 5);
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
