"use strict";

const { net } = require("electron");
const {
  changePercent,
  hasDrawableIntradayData,
  marketForSearchItem,
  parseTencentMinute,
  parseTrend,
  tencentCode,
} = require("./lib");

const SEARCH_TOKEN = "D43BF722C8E33DA55D5C6812C6C46";

async function requestJSON(url) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 15000);
  try {
    const response = await net.fetch(url, {
      signal: controller.signal,
      headers: {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
        Referer: "https://quote.eastmoney.com/",
      },
    });
    if (!response.ok) throw new Error(`Market data service returned ${response.status}`);
    return await response.json();
  } finally {
    clearTimeout(timeout);
  }
}

async function searchStocks(query) {
  const clean = String(query || "").trim();
  if (!clean) return [];
  const params = new URLSearchParams({
    input: clean,
    type: "14",
    token: SEARCH_TOKEN,
    count: "20",
  });
  const response = await requestJSON(`https://searchapi.eastmoney.com/api/suggest/get?${params}`);
  const table = response.QuotationCodeTable;
  if (!table || table.Status !== 0) throw new Error("Search service is temporarily unavailable");
  const seen = new Set();
  return (table.Data || []).flatMap((item) => {
    const market = marketForSearchItem(item);
    if (!market) return [];
    const quoteID = item.QuoteID || `${item.MktNum}.${item.Code}`;
    if (seen.has(quoteID)) return [];
    seen.add(quoteID);
    return [{
      code: item.Code,
      name: englishStockName(item.Name, item.Code),
      market,
      quoteID,
    }];
  });
}

async function fetchTencent(symbol) {
  const code = tencentCode(symbol);
  const response = await requestJSON(
    `https://web.ifzq.gtimg.cn/appstock/app/minute/query?code=${encodeURIComponent(code)}`,
  );
  const payload = response?.data?.[code];
  const quoteFields = payload?.qt?.[code];
  if (response?.code !== 0 || !payload || !Array.isArray(quoteFields) || quoteFields.length <= 5) {
    throw new Error("Unexpected Tencent intraday response");
  }
  const rawDate = payload.data?.date || String(quoteFields[30] || "").slice(0, 10);
  const points = (payload.data?.data || [])
    .map((item) => parseTencentMinute(item, rawDate))
    .filter(Boolean);
  if (!hasDrawableIntradayData(points)) {
    throw new Error("No complete intraday data is available today");
  }
  const lastPoint = points.at(-1);
  const dayOpen = Number(quoteFields[5]) > 0 ? Number(quoteFields[5]) : points[0].price;
  const previousClose = Number(quoteFields[4]) > 0 ? Number(quoteFields[4]) : dayOpen;
  const lastPrice = Number(quoteFields[3]) > 0 ? Number(quoteFields[3]) : lastPoint.price;
  return {
    symbol,
    points,
    dayOpen,
    previousClose,
    lastPrice,
    changePercent: changePercent(lastPrice, previousClose),
    updatedAt: lastPoint.time,
    isStale: false,
    source: "Tencent intraday",
  };
}

async function fetchEastmoney(symbol) {
  const params = new URLSearchParams({
    secid: symbol.quoteID,
    fields1: "f1,f2,f3,f4,f5,f6,f7,f8,f9,f10,f11,f12,f13",
    fields2: "f51,f52,f53,f54,f55,f56,f57,f58",
    iscr: "0",
    ndays: "1",
  });
  const response = await requestJSON(
    `https://push2delay.eastmoney.com/api/qt/stock/trends2/get?${params}`,
  );
  if (response?.rc !== 0 || !response.data) throw new Error("Eastmoney intraday data is unavailable");
  const points = (response.data.trends || []).map(parseTrend).filter(Boolean);
  if (!hasDrawableIntradayData(points)) {
    throw new Error("No complete intraday data is available today");
  }
  const dayOpen = points[0].open > 0 ? points[0].open : points[0].price;
  const previousClose = Number(response.data.preClose) > 0
    ? Number(response.data.preClose)
    : dayOpen;
  const lastPrice = points.at(-1).price;
  return {
    symbol,
    points,
    dayOpen,
    previousClose,
    lastPrice,
    changePercent: changePercent(lastPrice, previousClose),
    updatedAt: points.at(-1).time,
    isStale: false,
    source: "Eastmoney fallback",
  };
}

async function fetchIntraday(symbol) {
  try {
    return await fetchTencent(symbol);
  } catch {
    return await fetchEastmoney(symbol);
  }
}

module.exports = { fetchIntraday, searchStocks };

function englishStockName(sourceName, code) {
  const knownNames = {
    "600519": "Kweichow Moutai",
    "00700": "Tencent Holdings",
    AAPL: "Apple",
    "300308": "Zhongji Innolight",
    "07200": "CSOP HSI 2x Daily Long",
  };
  const normalizedCode = String(code || "").toUpperCase();
  if (knownNames[normalizedCode]) return knownNames[normalizedCode];
  return /[\u3400-\u9fff]/u.test(String(sourceName || ""))
    ? normalizedCode
    : String(sourceName || normalizedCode);
}
