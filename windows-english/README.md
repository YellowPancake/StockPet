# Stock Pet for Windows

Portable Windows x64 edition. Extract the complete archive, then run
`StockPet.exe`. Do not move the EXE out of its folder by itself.

## Features

- Real intraday charts for A-share, Hong Kong, and US markets, with no stock limit
- Transparent frameless overlay with dragging, scaling, always-on-top, and mouse passthrough
- Scrollable stock board and search results
- Tickers and markets are hidden by default so stock names can be larger; they can be enabled at any time
- Chart horizontal width and font size are independently adjustable; names, prices, and changes share the text opacity
- Red-up/green-down for A-share and Hong Kong markets; green-up/red-down for the US market
- Double-click the stock board to open Settings
- Customizable global shortcut to show or hide Stock Pet
- Bull and bear alerts can use previous-close percentages or per-stock target prices
- Live prices can generate upper and lower targets in one click; opacity and sounds remain configurable
- Latest prices, changes, and alerts can use 1-second batch refresh; charts update independently every 15 seconds or slower
- GitHub update checks download and verify the matching English Windows package without silently replacing the app
- Tencent fast quotes and intraday data are primary, with Eastmoney fallback and adaptive failure backoff

## Requirements

- Windows 10 64-bit or later
- Intel or AMD x64 processor

This build is not signed with a commercial code-signing certificate. Windows
SmartScreen may display a warning the first time it is opened.

## Local tests

```bash
node --test test/*.test.js
```
