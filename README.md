<p align="center">
  <img src="docs/assets/app-icon.png" width="112" alt="盘宠 StockPet 图标">
</p>

<h1 align="center">盘宠 StockPet</h1>

<p align="center">
  <strong>工作时也能及时关注股价变化，你的桌面股票盯盘搭子。</strong><br>
  把行情养在桌面上：分时线安静趴着，该提醒时，小牛小熊会自己来。
</p>

<p align="center">
  <strong>简体中文</strong> · <a href="README_EN.md">English</a>
</p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111111?logo=apple">
  <img alt="Windows 10/11" src="https://img.shields.io/badge/Windows-10%20%2F%2011-0078D4?logo=windows">
  <img alt="A股 港股 美股" src="https://img.shields.io/badge/市场-A股%20%7C%20港股%20%7C%20美股-EA4C61">
  <img alt="Version 0.3.0" src="https://img.shields.io/badge/version-0.3.0-5B67F1">
  <img alt="MIT License" src="https://img.shields.io/badge/license-MIT-4C9A2A">
</p>

<p align="center">
  <img src="docs/assets/hero-bull-alert.gif" width="680" alt="盘宠牛牛涨幅提醒演示">
</p>

## 目录

- [快速开始](#快速开始)
- [为什么会有盘宠？](#为什么会有盘宠)
- [平时，它安安静静](#平时它安安静静)
- [需要时，牛牛和小熊会来](#需要时牛牛和小熊会来)
- [融进桌面，也能随时收起来](#融进桌面也能随时收起来)
- [功能一览](#功能一览)
- [下载与安装](#下载与安装)
- [数据与风险说明](#数据与风险说明)
- [常见问题](#常见问题)
- [反馈与许可证](#反馈与许可证)
- [给作者加个鸡腿🍗~](#支持作者)

## 快速开始

先前往 [GitHub Releases](https://github.com/YellowPancake/StockPet/releases/latest)，下载中文 macOS Universal 或 Windows x64 安装包并启动。

1. **添加股票**：双击桌宠打开设置，搜索名称或代码，例如 `贵州茅台`、`00700`、`AAPL`。
2. **调成顺眼的样子**：设置整体大小，以及曲线、名称与数字、背景板的不透明度。
3. **交给牛熊值班**：选择按昨收涨跌幅或目标价格提醒，再设置一组顺手的显示 / 隐藏快捷键。

默认快捷键：

| 平台 | 显示 / 隐藏桌宠 |
| --- | --- |
| macOS | `⌘ + ⌥ + S` |
| Windows | `Ctrl + Alt + S` |

## 为什么会有盘宠？

在电脑前工作时，很难一直开着完整行情软件：窗口占地方，来回切换打断节奏，但错过关键涨跌又不放心。

盘宠把真正想看的内容——股票名称、当日分时线、最新价和涨跌幅——留在桌面角落。它不要求你一直盯盘，而是作为一个安静的**股票盯盘搭子**，让你专心工作时仍能及时感知股价变化；触及阈值时，牛牛或小熊会主动出来提醒。

你可以分别调低曲线、文字和背景板的不透明度，让行情淡淡融进桌面。**同事或老板从身边经过时，不会一眼看到一个醒目的看盘窗口，少一点被撞见摸鱼的尴尬。**

它还能缩小、拖到顺眼的位置，甚至让鼠标直接穿过去。需要专心、开会或共享屏幕时，一组快捷键就能让它暂时消失。

## 平时，它安安静静

<table>
  <tr>
    <td width="58%" align="center">
      <img src="docs/assets/screenshot-stock-list.png" alt="盘宠清晰显示模式">
    </td>
    <td width="42%" align="center">
      <img src="docs/assets/screenshot-low-profile.png" alt="盘宠低不透明度显示模式">
    </td>
  </tr>
  <tr>
    <td align="center"><sub>想看清楚时，信息完整展开</sub></td>
    <td align="center"><sub>想低调一点时，淡淡留在桌面</sub></td>
  </tr>
</table>

- 同时查看 A 股、港股和美股，股票数量不设上限。
- 每只股票展示真实的当日分时曲线，左侧名称，右侧最新价与涨跌幅。
- A 股、港股红涨绿跌；美股绿涨红跌。
- 股票名称、代码、市场、价格、涨跌幅与曲线保持同一涨跌色。
- 股票较多时直接在桌宠内滚动，不会无限撑高窗口。

## 需要时，牛牛和小熊会来

<p align="center">
  <img src="docs/assets/screenshot-alerts.png" width="640" alt="盘宠牛熊提醒设置">
</p>

- 支持两种提醒依据：按“最新价相对昨收的涨跌幅”，或为每只股票单独设置“小牛目标价 / 小熊目标价”。
- 目标价模式实时显示自选股最新价，可按现价一键生成上下目标，也可以逐只修改。
- 越过上涨阈值或小牛目标价时，小牛从行情板底部冒出来；跌破阈值或小熊目标价时，小熊会来敲警钟。
- 牛叫和熊叫可以分别开启或关闭，整个牛熊提醒也有总开关。
- 提醒卡片支持独立调节不透明度。
- 同一次越界只提醒一次；回到阈值内侧后才会重新布防，避免在边缘反复弹出。

<p align="center">
  <img src="docs/assets/screenshot-target-price-zh.jpg" width="640" alt="盘宠逐股目标价格提醒设置">
</p>

例如上涨阈值设为 `+3.0%`：首次达到 `+3.0%` 时提醒；回落到 `+2.85%` 以下后重新布防；再次达到 `+3.0%` 时才会再次提醒。

## 融进桌面，也能随时收起来

<p align="center">
  <img src="docs/assets/screenshot-appearance.png" width="640" alt="盘宠外观、交互与快捷键设置">
</p>

- **整体缩放**：从 `65%` 到 `160%`，股票、曲线和背景板一起变化。
- **三组不透明度**：曲线、名称与数字、背景板分别调节。
- **拖拽摆放**：放在桌面上任何顺眼的位置。
- **双击设置**：双击行情板或曲线即可打开设置。
- **快捷显示 / 隐藏**：全局快捷键可以开启、关闭和重新组合。
- **锁定并穿透鼠标**：不挡住下面窗口的点击和滚动。
- **始终置顶**：切换工作窗口时，行情仍留在视线边缘。

## 功能一览

| 能力 | 说明 |
| --- | --- |
| 多市场行情 | 搜索并添加 A 股、港股、美股 |
| 不限自选股数量 | 可添加、删除、排序；长列表支持滚动 |
| 当日分时曲线 | 展示真实分钟数据，不生成假曲线 |
| 市场配色 | A/H 红涨绿跌，美股绿涨红跌 |
| 外观控制 | 整体缩放，三组不透明度独立调节 |
| 桌面交互 | 拖拽、双击设置、始终置顶、鼠标穿透 |
| 快捷隐藏 | 可自定义全局快捷键，一键显示或隐藏 |
| 牛熊提醒 | 昨收涨跌幅或逐股目标价、实时价生成目标、总开关、不透明度、独立声音 |
| 防重复提醒 | `0.15` 个百分点 / `0.15%` 滞回重布防 |
| 行情容错 | 腾讯分时为主，东方财富备用；失败时标记过期数据 |
| 跨平台 | macOS Universal、Windows x64；各有中英文版 |

## 下载与安装

请前往 [GitHub Releases](https://github.com/YellowPancake/StockPet/releases/latest) 下载对应压缩包：

| 文件 | 语言与设备 |
| --- | --- |
| `StockPet-macOS-Chinese.zip` | 中文；Apple 芯片与 Intel 芯片 Mac |
| `StockPet-Windows-x64-Chinese.zip` | 中文；Windows 10/11 64 位 |
| `StockPet-macOS-English.zip` | English；Apple 芯片与 Intel 芯片 Mac |
| `StockPet-Windows-x64-English.zip` | English；Windows 10/11 64 位 |

### macOS

1. 解压 ZIP，把应用拖到“应用程序”。
2. 首次启动如果提示无法验证开发者，请到“系统设置 → 隐私与安全性”确认打开。
3. 盘宠是菜单栏应用；开启鼠标穿透后，可从菜单栏曲线图标解除。

系统要求：macOS 14 或更高版本。

### Windows

1. 完整解压 ZIP。
2. 进入解压后的文件夹，双击 `StockPet.exe`。
3. 不要只把 EXE 单独移走，它需要同目录下的 `resources`、`locales` 和 DLL 文件。
4. 开启鼠标穿透后，可从右下角系统托盘的 Stock Pet 图标解除。

系统要求：Windows 10/11 64 位。

> 当前发布包未使用商业代码签名证书，因此系统首次打开时可能显示来源提醒。

## 数据与风险说明

- 股票搜索覆盖 A 股、港股和美股。
- 腾讯分时行情为主数据源，东方财富作为故障备用。
- 刷新频率可在设置中调整。
- 接口失败时不会绘制随机或模拟曲线；有成功数据时会保留最后一次结果并标记为过期。
- 港股、美股实时权限受交易所授权规则约束，公开行情可能存在延迟、限流或调整。

> [!CAUTION]
> 盘宠仅用于个人辅助查看行情，不构成投资建议，也不应作为下单依据。公开网页行情不保证交易级实时性、完整性或准确性。任何投资决策及其结果由使用者自行承担。

## 常见问题

<details>
<summary><strong>能添加超过 10 只股票吗？</strong></summary>

可以。盘宠不限制股票数量；桌宠和搜索结果都支持上下滚动。股票很多时，刷新请求数量也会相应增加。

</details>

<details>
<summary><strong>为什么到达阈值后没有连续提醒？</strong></summary>

这是有意的防打扰设计。涨跌幅提醒触发后，需要先回到阈值内至少 `0.15` 个百分点；目标价提醒触发后，需要回到目标内侧至少 `0.15%`，盘宠才会重新布防。

</details>

<details>
<summary><strong>会不会挡住正常工作？</strong></summary>

可以降低三组不透明度、缩小整体尺寸、开启鼠标穿透，或使用全局快捷键直接隐藏。

</details>

## 反馈与许可证

遇到问题请提交 [Issue](https://github.com/YellowPancake/StockPet/issues)，并尽量附上系统版本、股票代码和复现步骤；请勿上传账户、交易或其他敏感信息。

本项目采用 [MIT License](LICENSE)。

<a id="支持作者"></a>

## 给作者加个鸡腿🍗~

如果盘宠帮你在认真工作时少错过了一次行情，也让摸鱼看盘少了一点尴尬，欢迎请作者加个鸡腿。感谢支持，也请量力而行～

<table>
  <tr>
    <td width="50%" align="center">
      <strong>微信支付</strong><br><br>
      <img src="docs/assets/donate-wechat.jpg" width="300" alt="微信支付打赏码">
    </td>
    <td width="50%" align="center">
      <strong>支付宝</strong><br><br>
      <img src="docs/assets/donate-alipay.jpg" width="300" alt="支付宝打赏码">
    </td>
  </tr>
</table>
