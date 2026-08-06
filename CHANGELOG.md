# Changelog

## v0.4.4

- Restored the minimum supported macOS version to 14 after real-device compatibility testing.
- Added a choice between percentage change and absolute price change on the desktop.
- Hardened Windows global shortcut registration so show/hide remains available while other applications are focused and after sleep or unlock.
- Added startup recovery and safer preference migration on macOS.
- Added index-aware search and quote routing for major A-share, Hong Kong, and US indices, fixing the `000001` Shanghai Composite / Ping An Bank collision.
- Added an optional daily local-time schedule for automatically showing and hiding Stock Pet.

## v0.4.3

- Improved settings-window startup and launch diagnostics.

## v0.4.2

- Added transparent multipart download and reassembly for routes with per-file size limits.
- The user still receives one verified ZIP; multipart storage is an internal implementation detail.

## v0.4.1

- Added two independent update routes for version checks and verified package downloads.
- Simplified update copy so the settings UI does not expose hosting-provider names.
- Kept manual installation: the app downloads and verifies the selected package, opens its folder, and never silently replaces itself.

## v0.4.0

- Added optional 1-second batch refresh for latest prices, percentage changes, and bull/bear alerts.
- Separated intraday chart refresh from fast quotes; charts update every 15 seconds or slower.
- Added market-hours throttling, overlapping-request protection, source timestamp filtering, and progressive retry backoff.
- Added in-app GitHub update checks and verified package downloads for all four language/platform builds. The app never silently replaces itself.

## v0.3.0

The first public release of 盘宠 StockPet.

### Highlights

- Native Universal macOS builds for Apple Silicon and Intel Macs.
- Portable Windows x64 builds.
- Separate Chinese and fully English editions.
- A-share, Hong Kong, and US intraday charts with unlimited watchlist entries.
- Market-aware red/green conventions and consistent chart, name, ticker, price, and change colors.
- Independent opacity controls, overall scaling, dragging, always-on-top, mouse passthrough, and a customizable global show/hide shortcut.
- Bull and bear alerts based on either change from the previous close or per-stock target prices.
- Live quote refresh with one-click target generation from the current price.
- Alert opacity, independent sounds, and hysteresis-based anti-repeat logic.

### Notes

- Public quote endpoints may be delayed, rate-limited, or changed and should not be treated as trading-grade data.
- The downloadable apps are not signed with a commercial code-signing certificate, so the operating system may show a source warning on first launch.
