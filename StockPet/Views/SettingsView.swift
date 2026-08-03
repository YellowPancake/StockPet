import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: StockStore
    @State private var query = ""
    @State private var results: [StockSymbol] = []
    @State private var isSearching = false
    @State private var searchMessage: String?
    @State private var selectedSection: SettingsSection = .watchlist
    @State private var isRefreshingAlertPrices = false
    @State private var alertPriceMessage: String?
    @State private var updateState: SoftwareUpdateUIState = .idle

    private static let updateService = SoftwareUpdateService()

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 145, ideal: 160)
        } detail: {
            Group {
                switch selectedSection {
                case .watchlist:
                    watchlistView
                case .appearance:
                    appearanceView
                case .alerts:
                    alertsView
                case .data:
                    dataView
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationTitle("Stock Pet 设置")
    }

    private var watchlistView: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageTitle("桌面股票", subtitle: "搜索名称或代码，股票数量不设上限")

            HStack(spacing: 8) {
                TextField("例如：贵州茅台、00700、AAPL", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { runSearch() }

                Button {
                    runSearch()
                } label: {
                    if isSearching {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("搜索", systemImage: "magnifyingglass")
                    }
                }
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
            }

            if let searchMessage {
                Label(searchMessage, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !results.isEmpty {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { symbol in
                            HStack {
                                MarketBadge(market: symbol.market)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(symbol.name).fontWeight(.semibold)
                                    Text(symbol.code).font(.caption.monospaced()).foregroundStyle(.secondary)
                                }
                                Spacer()
                            Button(tr(store.symbols.contains(symbol) ? "已添加" : "添加")) {
                                searchMessage = store.add(symbol)
                                if searchMessage == nil {
                                    searchMessage = String(
                                        format: tr("已把 %@ 放到桌面"),
                                        symbol.name
                                    )
                                }
                                }
                                .disabled(store.symbols.contains(symbol))
                            }
                            .padding(10)
                            if symbol.id != results.last?.id {
                                Divider()
                            }
                        }
                    }
                }
                .frame(maxHeight: 190)
                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            }

            HStack {
                Text("\(tr("当前")) \(store.symbols.count) \(tr("只"))")
                    .font(.headline)
                Spacer()
                Text("拖动右侧把手排序")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            List {
                ForEach(store.symbols) { symbol in
                    HStack(spacing: 10) {
                        MarketBadge(market: symbol.market)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(symbol.name).fontWeight(.semibold)
                            Text("\(symbol.code) · \(symbol.market.displayName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let quote = store.quotes[symbol.id] {
                            Text(String(format: "%@%.2f%%", quote.changePercent >= 0 ? "+" : "", quote.changePercent))
                                .font(.caption.bold().monospacedDigit())
                                .foregroundStyle(symbol.market.colorRole(isRising: quote.changePercent >= 0).color)
                        }
                        Button(role: .destructive) {
                            store.remove(symbol)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 3)
                }
                .onMove(perform: store.moveSymbols)
            }
            .listStyle(.inset)
            .frame(minHeight: 270)
        }
    }

    private var appearanceView: some View {
        VStack(alignment: .leading, spacing: 22) {
            pageTitle("外观与交互", subtitle: "让它融进桌面，而不是挡住工作")

            SettingsCard {
                HStack {
                    Label("整体大小", systemImage: "arrow.up.left.and.arrow.down.right")
                        .frame(width: 130, alignment: .leading)
                    Slider(value: $store.displayScale, in: 0.65...1.6, step: 0.05)
                    Text("\(Int(store.displayScale * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
                Divider()
                opacitySlider(
                    title: "曲线不透明度",
                    icon: "waveform.path.ecg",
                    value: $store.lineOpacity,
                    range: 0.15...1
                )
                Divider()
                HStack {
                    Label("曲线宽度", systemImage: "arrow.left.and.right")
                        .frame(width: 160, alignment: .leading)
                    Slider(value: $store.chartWidth, in: 160...650, step: 10)
                    Text("\(Int(store.chartWidth)) pt")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 58, alignment: .trailing)
                }
                Divider()
                opacitySlider(
                    title: "名称与数字不透明度",
                    icon: "textformat",
                    value: $store.labelOpacity,
                    range: 0.15...1
                )
                Divider()
                HStack {
                    Label("字体大小", systemImage: "textformat.size")
                        .frame(width: 160, alignment: .leading)
                    Slider(value: $store.fontScale, in: 0.75...1.5, step: 0.05)
                    Text("\(Int(store.fontScale * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
                Divider()
                Toggle(isOn: $store.showStockMeta) {
                    Label("显示股票代码与市场", systemImage: "number.square")
                }
                Divider()
                opacitySlider(
                    title: "背景板不透明度",
                    icon: "square.on.square",
                    value: $store.backgroundOpacity,
                    range: 0...0.55
                )
            }

            SettingsCard {
                Toggle(isOn: $store.compactMode) {
                    Label("紧凑模式", systemImage: "rectangle.compress.vertical")
                }
                Divider()
                Toggle(isOn: $store.alwaysOnTop) {
                    Label("始终置顶", systemImage: "pin.fill")
                }
                Divider()
                VStack(alignment: .leading, spacing: 5) {
                    Toggle(isOn: $store.clickThrough) {
                        Label("锁定并穿透鼠标", systemImage: "cursorarrow.slash")
                    }
                    Text("锁定后需从菜单栏的曲线图标关闭穿透。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsCard {
                Toggle(isOn: $store.shortcutEnabled) {
                    Label("快捷键显示/隐藏桌宠", systemImage: "keyboard")
                }
                Divider()
                HStack {
                    Text("快捷键组合")
                    Spacer()
                    Picker("", selection: $store.shortcutModifier) {
                        ForEach(ShortcutModifierOption.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 86)

                    Text("+")
                        .foregroundStyle(.secondary)

                    Picker("", selection: $store.shortcutKey) {
                        ForEach(ShortcutKeyOption.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 78)
                }
                .disabled(!store.shortcutEnabled)
                .opacity(store.shortcutEnabled ? 1 : 0.45)
            }

            Button("恢复默认外观") {
                store.resetAppearance()
            }
        }
    }

    private var alertsView: some View {
        VStack(alignment: .leading, spacing: 22) {
            pageTitle(
                "牛熊提醒",
                subtitle: store.alertBasis == .percentage
                    ? "涨跌幅以昨收为基准，每次越过阈值只提醒一次"
                    : "为每只股票设置小牛价和小熊价，触达目标价格时提醒"
            )

            SettingsCard {
                Toggle(isOn: $store.alertsEnabled) {
                    Label("开启牛熊提醒", systemImage: "bell.badge.fill")
                }
                Divider()
                HStack {
                    Label("提醒依据", systemImage: "scope")
                    Spacer()
                    Picker("", selection: $store.alertBasis) {
                        ForEach(AlertBasis.allCases) { basis in
                            Text(basis.displayName).tag(basis)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 260)
                }
                Divider()
                Group {
                    if store.alertBasis == .percentage {
                        thresholdRow(
                            title: "上涨超过",
                            mascot: "🐂",
                            value: $store.risingThreshold,
                            color: .red
                        )
                        Divider()
                        thresholdRow(
                            title: "下跌超过",
                            mascot: "🐻",
                            value: $store.fallingThreshold,
                            color: .green
                        )
                    } else {
                        priceAlertControls
                    }
                    Divider()
                    opacitySlider(
                        title: "提醒不透明度",
                        icon: "circle.lefthalf.filled",
                        value: $store.alertOpacity,
                        range: 0.2...1
                    )
                    Divider()
                    Toggle(isOn: $store.bullSoundEnabled) {
                        Label("小牛提示音（短促牛叫）", systemImage: "speaker.wave.2.fill")
                    }
                    Divider()
                    Toggle(isOn: $store.bearSoundEnabled) {
                        Label("小熊提示音（短促吼声）", systemImage: "speaker.wave.2.fill")
                    }
                }
                .disabled(!store.alertsEnabled)
                .opacity(store.alertsEnabled ? 1 : 0.45)
            }

            Text(
                tr(
                    store.alertBasis == .percentage
                        ? "股票回到阈值内至少 0.15 个百分点后会重新布防，防止价格在边缘波动时连续弹出。"
                        : "目标价提醒触发后，价格回到目标内侧至少 0.15% 才会重新布防。行情按刷新频率持续更新。"
                )
            )
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Button("预览小牛与牛叫声") {
                    store.testAlert(.rising)
                }
                Button("预览小熊与短吼声") {
                    store.testAlert(.falling)
                }
            }
        }
    }

    private var priceAlertControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("实时价格与逐股目标")
                        .fontWeight(.semibold)
                    Text("先刷新实时价，再一键生成目标或手动调整")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    refreshAlertPrices(generateTargets: false)
                } label: {
                    if isRefreshingAlertPrices {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("刷新实时价", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isRefreshingAlertPrices)
                Button("按现价生成目标") {
                    refreshAlertPrices(generateTargets: true)
                }
                .disabled(isRefreshingAlertPrices)
            }

            if let alertPriceMessage {
                Text(alertPriceMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(store.symbols) { symbol in
                        priceAlertRow(for: symbol)
                        if symbol.id != store.symbols.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .frame(maxHeight: 230)
        }
    }

    private func priceAlertRow(for symbol: StockSymbol) -> some View {
        let quote = store.quotes[symbol.id]
        let targets = store.priceAlertTargets[symbol.id]
            ?? PriceAlertTargets(risingPrice: 0, fallingPrice: 0)
        let hasLivePrice = (quote?.lastPrice ?? 0) > 0

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { targets.isEnabled },
                        set: { store.setPriceTargetsEnabled(for: symbol, enabled: $0) }
                    )
                )
                .labelsHidden()
                .disabled(!hasLivePrice && !targets.isEnabled)

                VStack(alignment: .leading, spacing: 2) {
                    Text(symbol.name).fontWeight(.semibold)
                    Text("\(symbol.code) · \(symbol.market.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let quote {
                    Text(
                        String(
                            format: tr("现价 %@%.2f"),
                            symbol.market.currencySymbol,
                            quote.lastPrice
                        )
                    )
                    .font(.body.bold().monospacedDigit())
                } else {
                    Text("等待实时价")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                priceField(
                    title: "🐂 小牛价 ≥",
                    symbol: symbol,
                    isRising: true,
                    value: targets.risingPrice
                )
                priceField(
                    title: "🐻 小熊价 ≤",
                    symbol: symbol,
                    isRising: false,
                    value: targets.fallingPrice
                )
            }
            .disabled(!targets.isEnabled)
            .opacity(targets.isEnabled ? 1 : 0.42)
        }
        .padding(.vertical, 9)
    }

    private func priceField(
        title: String,
        symbol: StockSymbol,
        isRising: Bool,
        value: Double
    ) -> some View {
        HStack(spacing: 6) {
            Text(tr(title))
                .font(.caption)
            Text(symbol.market.currencySymbol)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(
                "",
                value: Binding(
                    get: { value },
                    set: { newValue in
                        let current = store.priceAlertTargets[symbol.id]
                            ?? PriceAlertTargets(risingPrice: 0, fallingPrice: 0)
                        store.updatePriceTargets(
                            for: symbol,
                            risingPrice: isRising ? newValue : current.risingPrice,
                            fallingPrice: isRising ? current.fallingPrice : newValue
                        )
                    }
                ),
                format: .number.precision(.fractionLength(2))
            )
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: 92)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func refreshAlertPrices(generateTargets: Bool) {
        isRefreshingAlertPrices = true
        alertPriceMessage = nil
        Task {
            await store.refreshAll()
            if generateTargets {
                let count = store.generatePriceTargetsFromCurrentQuotes()
                alertPriceMessage = String(
                    format: tr("已按当前价为 %d 只股票生成目标"),
                    count
                )
            } else {
                alertPriceMessage = tr("实时价格已刷新")
            }
            isRefreshingAlertPrices = false
        }
    }

    private var dataView: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 22) {
                pageTitle("数据与刷新")

            SettingsCard {
                HStack {
                    Label("刷新频率", systemImage: "arrow.clockwise")
                    Spacer()
                    Picker("", selection: $store.refreshInterval) {
                        Text("1 秒（极速）").tag(1)
                        Text("5 秒").tag(5)
                        Text("10 秒").tag(10)
                        Text("15 秒").tag(15)
                        Text("30 秒").tag(30)
                        Text("60 秒").tag(60)
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
                Text("最新价、涨跌幅和牛熊提醒按所选频率更新；分时曲线最快每 15 秒更新一次。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider()
                LabeledContent(
                    "当前数据源",
                    value: tr("腾讯秒级报价 · 腾讯分时 · 东方财富备用")
                )
                Divider()
                LabeledContent(
                    "最近刷新",
                    value: store.lastRefresh?.formatted(
                        Date.FormatStyle(
                            date: .abbreviated,
                            time: .standard,
                            locale: stockPetLocale,
                            calendar: .current,
                            timeZone: .current
                        )
                    ) ?? tr("尚未连接")
                )
            }

            Button {
                Task { await store.refreshAll() }
            } label: {
                Label("立即刷新全部股票", systemImage: "arrow.clockwise")
            }

            GroupBox("使用说明") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("• 本应用仅用于个人辅助查看，不构成投资建议。")
                    Text("• 公开网页行情可能延迟、限流或调整，不应用于下单决策。")
                    Text("• 港股、美股实时权限受交易所授权约束；若需要交易级数据，可后续接入富途 OpenD 或券商行情。")
                    Text("• 接口失败时不会生成假曲线，只保留最后一次成功数据并标记为过期。")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            SettingsCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("软件更新", systemImage: "arrow.triangle.2.circlepath")
                            .fontWeight(.semibold)
                        Spacer()
                        Text("v\(currentAppVersion)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    softwareUpdateContent
                }
            }

                SettingsCard {
                    HStack {
                        Label("GitHub 作者", systemImage: "person.crop.circle")
                        Spacer()
                        Link("@YellowPancake", destination: URL(string: "https://github.com/YellowPancake")!)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var softwareUpdateContent: some View {
        switch updateState {
        case .idle:
            HStack {
                Text("检查 GitHub 上是否有新版本，并下载适用于当前系统和语言的安装包。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("检查更新") { checkSoftwareUpdate() }
            }
        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在检查更新…").font(.caption).foregroundStyle(.secondary)
            }
        case .upToDate:
            HStack {
                Label("已经是最新版本", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Spacer()
                Button("重新检查") { checkSoftwareUpdate() }
            }
        case .available(let update):
            VStack(alignment: .leading, spacing: 10) {
                Label(
                    String(format: tr("发现新版本 v%@"), update.version),
                    systemImage: "sparkles"
                )
                .fontWeight(.semibold)
                if !update.notes.isEmpty {
                    Text(update.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
                HStack {
                    Button("下载更新包") { downloadSoftwareUpdate(update) }
                    Link("查看发布页面", destination: update.releasePageURL)
                        .font(.caption)
                }
            }
        case .downloading(let version):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(String(format: tr("正在下载并校验 v%@…"), version))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .downloaded(let fileURL):
            HStack {
                Label("更新包已下载并通过校验", systemImage: "checkmark.shield.fill")
                    .foregroundStyle(.green)
                Spacer()
                Button("在访达中显示") {
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                }
            }
        case .failed(let message):
            HStack {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                Spacer()
                Button("重试") { checkSoftwareUpdate() }
            }
        }
    }

    private var currentAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.4.0"
    }

    private var updateAssetName: String {
#if ENGLISH_BUILD
        "StockPet-macOS-English.zip"
#else
        "StockPet-macOS-Chinese.zip"
#endif
    }

    private func checkSoftwareUpdate() {
        updateState = .checking
        Task {
            do {
                let result = try await Self.updateService.check(
                    currentVersion: currentAppVersion,
                    assetName: updateAssetName
                )
                switch result {
                case .upToDate:
                    updateState = .upToDate
                case .available(let update):
                    updateState = .available(update)
                }
            } catch {
                updateState = .failed(error.localizedDescription)
            }
        }
    }

    private func downloadSoftwareUpdate(_ update: AvailableSoftwareUpdate) {
        updateState = .downloading(version: update.version)
        Task {
            do {
                let fileURL = try await Self.updateService.download(update)
                updateState = .downloaded(fileURL)
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            } catch {
                updateState = .failed(error.localizedDescription)
            }
        }
    }

    private func runSearch() {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else { return }
        isSearching = true
        searchMessage = nil
        results = []

        Task {
            do {
                let found = try await store.search(cleanQuery)
                results = found
                searchMessage = found.isEmpty ? tr("没有找到支持的 A股、港股或美股") : nil
            } catch {
#if ENGLISH_BUILD
                searchMessage = tr("搜索暂时不可用")
#else
                searchMessage = String(
                    format: tr("搜索失败：%@"),
                    error.localizedDescription
                )
#endif
            }
            isSearching = false
        }
    }

    private func pageTitle(_ title: String, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(tr(title))
                .font(.system(size: 24, weight: .bold, design: .rounded))
            if let subtitle, !subtitle.isEmpty {
                Text(tr(subtitle))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func opacitySlider(
        title: String,
        icon: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        HStack {
            Label(tr(title), systemImage: icon)
                .frame(width: 160, alignment: .leading)
            Slider(value: value, in: range)
            Text("\(Int(value.wrappedValue * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }

    private func thresholdRow(
        title: String,
        mascot: String,
        value: Binding<Double>,
        color: Color
    ) -> some View {
        HStack(spacing: 12) {
            Text(mascot).font(.system(size: 25))
            Text(tr(title)).frame(width: 80, alignment: .leading)
            Slider(value: value, in: 0.5...15, step: 0.5)
                .tint(color)
            Text(String(format: "%.1f%%", value.wrappedValue))
                .font(.body.bold().monospacedDigit())
                .frame(width: 52, alignment: .trailing)
        }
    }
}

private enum SoftwareUpdateUIState {
    case idle
    case checking
    case upToDate
    case available(AvailableSoftwareUpdate)
    case downloading(version: String)
    case downloaded(URL)
    case failed(String)
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case watchlist
    case appearance
    case alerts
    case data

    var id: String { rawValue }

    var title: String {
        switch self {
        case .watchlist: tr("桌面股票")
        case .appearance: tr("外观与交互")
        case .alerts: tr("牛熊提醒")
        case .data: tr("数据与刷新")
        }
    }

    var icon: String {
        switch self {
        case .watchlist: "list.star"
        case .appearance: "paintbrush"
        case .alerts: "bell.badge"
        case .data: "network"
        }
    }
}

private struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 14) {
            content
        }
        .padding(16)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct MarketBadge: View {
    let market: StockMarket

    var body: some View {
        Text(market.displayName)
            .font(.caption2.bold())
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .foregroundStyle(.white)
            .background(badgeColor, in: Capsule())
    }

    private var badgeColor: Color {
        switch market {
        case .aShare: .red.opacity(0.78)
        case .hongKong: .orange.opacity(0.82)
        case .unitedStates: .blue.opacity(0.82)
        }
    }
}
