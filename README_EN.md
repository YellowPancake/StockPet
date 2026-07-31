<p align="center">
  <img src="docs/assets/app-icon.png" width="112" alt="Stock Pet icon">
</p>

<h1 align="center">Stock Pet</h1>

<p align="center">
  <strong>Your desktop stock-watching companion—stay aware of price moves while you work.</strong><br>
  Keep the market on your desktop: quiet intraday charts, with a little bull or bear when something matters.
</p>

<p align="center">
  <a href="README.md">Chinese</a> · <strong>English</strong>
</p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111111?logo=apple">
  <img alt="Windows 10/11" src="https://img.shields.io/badge/Windows-10%20%2F%2011-0078D4?logo=windows">
  <img alt="A-share HK US" src="https://img.shields.io/badge/Markets-A--share%20%7C%20HK%20%7C%20US-EA4C61">
  <img alt="Version 0.3.0" src="https://img.shields.io/badge/version-0.3.0-5B67F1">
  <img alt="MIT License" src="https://img.shields.io/badge/license-MIT-4C9A2A">
</p>

<p align="center">
  <img src="docs/assets/hero-bull-alert.gif" width="680" alt="Stock Pet bull alert demo">
</p>

## Contents

- [Quick start](#quick-start)
- [Why Stock Pet?](#why-stock-pet)
- [Quiet while you work](#quiet-while-you-work)
- [The bull and bear know when to interrupt](#the-bull-and-bear-know-when-to-interrupt)
- [Blend in, then disappear in one keystroke](#blend-in-then-disappear-in-one-keystroke)
- [Feature overview](#feature-overview)
- [Downloads and installation](#downloads-and-installation)
- [Data and risk notes](#data-and-risk-notes)
- [FAQ](#faq)
- [Feedback and license](#feedback-and-license)
- [Buy the author a chicken leg 🍗~](#support-the-author)

## Quick start

First visit [GitHub Releases](https://github.com/YellowPancake/StockPet/releases/latest), download the English Universal macOS or Windows x64 package, and launch it.

1. **Add stocks:** double-click the pet, then search by company name or ticker, such as `Kweichow Moutai`, `00700`, or `AAPL`.
2. **Make it yours:** adjust overall size and the separate chart, text/number, and background opacity controls.
3. **Put the animals on duty:** choose previous-close percentage or target-price alerts, then set a convenient show/hide shortcut.

Default shortcut:

| Platform | Show / hide Stock Pet |
| --- | --- |
| macOS | `⌘ + ⌥ + S` |
| Windows | `Ctrl + Alt + S` |

## Why Stock Pet?

Keeping a full trading app open while working takes space and interrupts your flow—but missing an important price move is not ideal either.

Stock Pet keeps only the useful pieces in a corner of your desktop: company name, today's intraday chart, latest price, and percentage change. It is a quiet **stock-watching companion** that helps you stay aware of market moves without staring at a trading window all day. When a threshold is crossed, a cartoon bull or bear comes out to tell you.

Independently lower the opacity of charts, text, and the background so the market quietly blends into your desktop. **A coworker or manager glancing at your screen is far less likely to see a conspicuous trading window—making casual market checks much less awkward.**

You can also resize it, drag it into a quiet corner, or let mouse clicks pass straight through. When you need a clean screen, join a meeting, or start sharing, one shortcut hides it instantly.

## Quiet while you work

<p align="center">
  <img src="docs/assets/screenshot-stock-list-en.jpg" width="680" alt="Stock Pet English desktop watchlist">
</p>

- Watch A-shares, Hong Kong stocks, and US stocks together, with no watchlist limit.
- Every stock has a real intraday chart, with the name on the left and latest price and change on the right.
- A-shares and Hong Kong stocks use red for gains and green for losses; US stocks use the opposite convention.
- Names, tickers, markets, prices, percentage changes, and charts share the same movement color.
- Long watchlists scroll inside the pet instead of growing forever.

## The bull and bear know when to interrupt

<p align="center">
  <img src="docs/assets/screenshot-bull-alert-en.jpg" width="560" alt="Stock Pet English bull threshold alert">
</p>

- Choose between change from the previous close and per-stock target prices.
- Target-price mode shows the latest quote for every watchlist stock. Generate upper and lower targets from the current price, then fine-tune each stock manually.
- A cartoon bull or bear appears when a stock crosses its percentage threshold or target price.
- Bull and bear sounds have independent switches, and all alerts can be disabled with one master switch.
- Alert opacity is adjustable on its own.
- Each crossing alerts once. The price must return inside the threshold before the alert re-arms, preventing chatter around the boundary.

<p align="center">
  <img src="docs/assets/screenshot-target-price-en.jpg" width="640" alt="Stock Pet English per-stock target price settings">
</p>

For example, with a `+3.0%` rise threshold: the first touch at `+3.0%` alerts; a pullback below `+2.85%` re-arms it; only a new move to `+3.0%` alerts again.

## Blend in, then disappear in one keystroke

<p align="center">
  <img src="docs/assets/screenshot-appearance-en.jpg" width="680" alt="Stock Pet English appearance and shortcut settings">
</p>

- **Overall scale:** resize the watchlist, charts, and panel together from `65%` to `160%`.
- **Three opacity controls:** tune charts, text and numbers, and the background independently.
- **Drag anywhere:** keep it wherever it feels least distracting.
- **Double-click settings:** double-click the panel or a chart to open Settings.
- **Global show/hide shortcut:** enable it, disable it, or choose a different combination.
- **Mouse passthrough:** lock the pet so it never blocks clicks or scrolling below it.
- **Always on top:** keep the market at the edge of your view while switching apps.

## Feature overview

| Feature | What it does |
| --- | --- |
| Three markets | Search and add A-shares, Hong Kong stocks, and US stocks |
| Unlimited watchlist | Add, remove, and reorder stocks; long lists scroll |
| Real intraday charts | Displays minute data and never invents a fake curve |
| Market-aware colors | A/H: red up, green down; US: green up, red down |
| Appearance controls | Overall scale plus three independent opacity settings |
| Desktop interaction | Drag, double-click Settings, always-on-top, and mouse passthrough |
| Quick hiding | Customizable global shortcut to show or hide the pet |
| Bull & bear alerts | Previous-close percentages or per-stock targets, live-price generation, master switch, opacity, and sounds |
| Anti-repeat logic | Re-arms with percentage or target-price hysteresis |
| Data resilience | Tencent primary, Eastmoney fallback, stale-data marking on failure |
| Cross-platform | Universal macOS and Windows x64, each in Chinese and English |

## Downloads and installation

Download one of the four packages from [GitHub Releases](https://github.com/YellowPancake/StockPet/releases/latest):

| File | Language and platform |
| --- | --- |
| `StockPet-macOS-Chinese.zip` | Chinese; Apple Silicon and Intel Macs |
| `StockPet-Windows-x64-Chinese.zip` | Chinese; 64-bit Windows 10/11 |
| `StockPet-macOS-English.zip` | English; Apple Silicon and Intel Macs |
| `StockPet-Windows-x64-English.zip` | English; 64-bit Windows 10/11 |

### macOS

1. Unzip the package and drag the app into Applications.
2. If macOS cannot verify the developer on first launch, confirm it under System Settings → Privacy & Security.
3. Stock Pet is a menu bar app. If mouse passthrough is enabled, use the chart icon in the menu bar to turn it off.

Requires macOS 14 or later.

### Windows

1. Extract the complete archive.
2. Open its folder and run `StockPet.exe`.
3. Do not move the EXE out by itself; it needs the adjacent `resources`, `locales`, and DLL files.
4. If mouse passthrough is enabled, use the Stock Pet icon in the Windows system tray to turn it off.

Requires 64-bit Windows 10 or 11.

> These builds are not signed with a commercial code-signing certificate, so the operating system may show a source warning on first launch.

## Data and risk notes

- Search covers A-shares, Hong Kong stocks, and US stocks.
- Tencent intraday quotes are the primary source; Eastmoney is the fallback.
- Refresh frequency is configurable.
- A failed request never creates a random or simulated chart. The last successful result may remain visible and is marked stale.
- Real-time entitlements for Hong Kong and US markets are subject to exchange rules. Public quote endpoints may be delayed, rate-limited, or changed.

> [!CAUTION]
> Stock Pet is a personal market-viewing aid, not investment advice and not a trading-data service. Public web quotes are not guaranteed to be real-time, complete, or accurate. You remain responsible for every investment decision and outcome.

## FAQ

<details>
<summary><strong>Can I add more than 10 stocks?</strong></summary>

Yes. Stock Pet has no watchlist limit, and both the desktop list and search results can scroll. Larger watchlists also create more refresh requests.

</details>

<details>
<summary><strong>Why does an alert not repeat continuously at the threshold?</strong></summary>

That is intentional. Percentage alerts re-arm after the change moves at least `0.15` points inside the threshold; target-price alerts re-arm after the price moves at least `0.15%` back inside the target.

</details>

<details>
<summary><strong>Will it get in the way of normal work?</strong></summary>

Lower the three opacity controls, reduce the overall size, enable mouse passthrough, or hide it instantly with the global shortcut.

</details>

## Feedback and license

Open an [Issue](https://github.com/YellowPancake/StockPet/issues) with your operating system, ticker, and reproduction steps. Please do not upload account, trading, or other sensitive information.

Stock Pet is released under the [MIT License](LICENSE).

<a id="support-the-author"></a>

## Buy the author a chicken leg 🍗~

If Stock Pet helped you catch a market move without breaking your workday—or made a quick market check a little less awkward—you can buy the author a chicken leg. Thank you, and please only contribute if you are comfortable doing so.

<table>
  <tr>
    <td width="50%" align="center">
      <strong>WeChat Pay</strong><br><br>
      <img src="docs/assets/donate-wechat.jpg" width="300" alt="WeChat Pay donation QR code">
    </td>
    <td width="50%" align="center">
      <strong>Alipay</strong><br><br>
      <img src="docs/assets/donate-alipay.jpg" width="300" alt="Alipay donation QR code">
    </td>
  </tr>
</table>
