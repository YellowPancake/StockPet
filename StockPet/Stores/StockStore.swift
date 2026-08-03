import AppKit
import Foundation

@MainActor
final class StockStore: ObservableObject {
    @Published var symbols: [StockSymbol] {
        didSet { persist() }
    }
    @Published private(set) var quotes: [String: StockQuote] = [:]
    @Published private(set) var loadingIDs = Set<String>()
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var sourceError: String?
    @Published var activeAlert: ThresholdAlert?

    @Published var lineOpacity: Double {
        didSet { persist() }
    }
    @Published var chartWidth: Double {
        didSet { persist() }
    }
    @Published var labelOpacity: Double {
        didSet { persist() }
    }
    @Published var fontScale: Double {
        didSet { persist() }
    }
    @Published var showStockMeta: Bool {
        didSet { persist() }
    }
    @Published var backgroundOpacity: Double {
        didSet { persist() }
    }
    @Published var risingThreshold: Double {
        didSet {
            thresholdGates.removeAll()
            persist()
        }
    }
    @Published var fallingThreshold: Double {
        didSet {
            thresholdGates.removeAll()
            persist()
        }
    }
    @Published var alertBasis: AlertBasis {
        didSet {
            thresholdGates.removeAll()
            persist()
        }
    }
    @Published var priceAlertTargets: [String: PriceAlertTargets] {
        didSet {
            thresholdGates.removeAll()
            persist()
        }
    }
    @Published var refreshInterval: Int {
        didSet {
            persist()
            restartRefreshLoop()
        }
    }
    @Published var clickThrough: Bool {
        didSet { persist() }
    }
    @Published var alwaysOnTop: Bool {
        didSet { persist() }
    }
    @Published var compactMode: Bool {
        didSet { persist() }
    }
    @Published var displayScale: Double {
        didSet { persist() }
    }
    @Published var bullSoundEnabled: Bool {
        didSet { persist() }
    }
    @Published var bearSoundEnabled: Bool {
        didSet { persist() }
    }
    @Published var alertsEnabled: Bool {
        didSet {
            if !alertsEnabled {
                activeAlert = nil
                currentAlertSound?.stop()
            }
            thresholdGates.removeAll()
            persist()
        }
    }
    @Published var alertOpacity: Double {
        didSet { persist() }
    }
    @Published var shortcutEnabled: Bool {
        didSet {
            persist()
            notifyShortcutChanged()
        }
    }
    @Published var shortcutModifier: ShortcutModifierOption {
        didSet {
            persist()
            notifyShortcutChanged()
        }
    }
    @Published var shortcutKey: ShortcutKeyOption {
        didSet {
            persist()
            notifyShortcutChanged()
        }
    }

    private let service: any QuoteProviding
    private let defaults: UserDefaults
    private var refreshTask: Task<Void, Never>?
    private var dismissAlertTask: Task<Void, Never>?
    private var currentAlertSound: NSSound?
    private var thresholdGates: [String: ThresholdGate] = [:]
    private var hasStarted = false

    init(
        service: any QuoteProviding = MarketQuoteService(),
        defaults: UserDefaults = .standard
    ) {
        self.service = service
        self.defaults = defaults

        if let data = defaults.data(forKey: Keys.symbols),
           let decoded = try? JSONDecoder().decode([StockSymbol].self, from: data) {
            symbols = decoded
        } else {
            symbols = StockSymbol.initialSymbols
        }
        lineOpacity = defaults.object(forKey: Keys.lineOpacity) as? Double ?? 0.92
        chartWidth = defaults.object(forKey: Keys.chartWidth) as? Double ?? 310
        labelOpacity = defaults.object(forKey: Keys.labelOpacity) as? Double ?? 0.92
        fontScale = defaults.object(forKey: Keys.fontScale) as? Double ?? 1.0
        showStockMeta = defaults.object(forKey: Keys.showStockMeta) as? Bool ?? false
        backgroundOpacity = defaults.object(forKey: Keys.backgroundOpacity) as? Double ?? 0.16
        risingThreshold = defaults.object(forKey: Keys.risingThreshold) as? Double ?? 3.0
        fallingThreshold = defaults.object(forKey: Keys.fallingThreshold) as? Double ?? 3.0
        alertBasis = AlertBasis(
            rawValue: defaults.string(forKey: Keys.alertBasis) ?? ""
        ) ?? .percentage
        if let data = defaults.data(forKey: Keys.priceAlertTargets),
           let decoded = try? JSONDecoder().decode([String: PriceAlertTargets].self, from: data) {
            priceAlertTargets = decoded
        } else {
            priceAlertTargets = [:]
        }
        refreshInterval = defaults.object(forKey: Keys.refreshInterval) as? Int ?? 15
        clickThrough = defaults.object(forKey: Keys.clickThrough) as? Bool ?? false
        alwaysOnTop = defaults.object(forKey: Keys.alwaysOnTop) as? Bool ?? true
        compactMode = defaults.object(forKey: Keys.compactMode) as? Bool ?? false
        displayScale = defaults.object(forKey: Keys.displayScale) as? Double ?? 1.0
        bullSoundEnabled = defaults.object(forKey: Keys.bullSoundEnabled) as? Bool ?? true
        bearSoundEnabled = defaults.object(forKey: Keys.bearSoundEnabled) as? Bool ?? true
        alertsEnabled = defaults.object(forKey: Keys.alertsEnabled) as? Bool ?? true
        alertOpacity = defaults.object(forKey: Keys.alertOpacity) as? Double ?? 0.94
        shortcutEnabled = defaults.object(forKey: Keys.shortcutEnabled) as? Bool ?? true
        shortcutModifier = ShortcutModifierOption(
            rawValue: defaults.string(forKey: Keys.shortcutModifier) ?? ""
        ) ?? .commandOption
        shortcutKey = ShortcutKeyOption(
            rawValue: defaults.string(forKey: Keys.shortcutKey) ?? ""
        ) ?? .s
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        restartRefreshLoop()
    }

    func stop() {
        hasStarted = false
        refreshTask?.cancel()
        refreshTask = nil
    }

    func search(_ query: String) async throws -> [StockSymbol] {
        try await service.search(query: query)
    }

    @discardableResult
    func add(_ symbol: StockSymbol) -> String? {
        guard !symbols.contains(where: { $0.id == symbol.id }) else {
            return tr("这只股票已经在桌面上了")
        }
        symbols.append(symbol)
        Task { await refresh(symbol) }
        return nil
    }

    func remove(_ symbol: StockSymbol) {
        symbols.removeAll { $0.id == symbol.id }
        quotes.removeValue(forKey: symbol.id)
        loadingIDs.remove(symbol.id)
        thresholdGates.removeValue(forKey: symbol.id)
        priceAlertTargets.removeValue(forKey: symbol.id)
    }

    func moveSymbols(from offsets: IndexSet, to destination: Int) {
        symbols.move(fromOffsets: offsets, toOffset: destination)
    }

    func refreshAll() async {
        let currentSymbols = symbols
        guard !currentSymbols.isEmpty else {
            lastRefresh = Date()
            sourceError = nil
            return
        }

        loadingIDs.formUnion(currentSymbols.map(\.id))
        var failures = 0

        await withTaskGroup(of: FetchOutcome.self) { group in
            for symbol in currentSymbols {
                group.addTask { [service] in
                    do {
                        return .success(try await service.fetchIntraday(for: symbol))
                    } catch {
                        return .failure(symbol.id, error.localizedDescription)
                    }
                }
            }

            for await outcome in group {
                switch outcome {
                case .success(let quote):
                    quotes[quote.id] = quote
                    loadingIDs.remove(quote.id)
                    evaluateThreshold(for: quote)
                case .failure(let id, let message):
                    failures += 1
                    loadingIDs.remove(id)
                    if var cached = quotes[id] {
                        cached.isStale = true
#if ENGLISH_BUILD
                        cached.statusMessage = tr("行情连接失败")
#else
                        cached.statusMessage = message
#endif
                        quotes[id] = cached
                    }
                }
            }
        }

        lastRefresh = Date()
        sourceError = failures == currentSymbols.count
            ? tr("行情连接暂不可用，已保留上次成功数据")
            : nil
    }

    func refresh(_ symbol: StockSymbol) async {
        loadingIDs.insert(symbol.id)
        do {
            let quote = try await service.fetchIntraday(for: symbol)
            quotes[symbol.id] = quote
            evaluateThreshold(for: quote)
        } catch {
            if var cached = quotes[symbol.id] {
                cached.isStale = true
#if ENGLISH_BUILD
                cached.statusMessage = tr("行情连接失败")
#else
                cached.statusMessage = error.localizedDescription
#endif
                quotes[symbol.id] = cached
            }
        }
        loadingIDs.remove(symbol.id)
    }

    func resetAppearance() {
        lineOpacity = 0.92
        chartWidth = 310
        labelOpacity = 0.92
        fontScale = 1.0
        showStockMeta = false
        backgroundOpacity = 0.16
        compactMode = false
        displayScale = 1.0
    }

    func updatePriceTargets(
        for symbol: StockSymbol,
        risingPrice: Double,
        fallingPrice: Double
    ) {
        let sanitized = PriceAlertTargets(
            risingPrice: risingPrice.isFinite ? max(0, risingPrice) : 0,
            fallingPrice: fallingPrice.isFinite ? max(0, fallingPrice) : 0
        )
        if sanitized.isEnabled {
            priceAlertTargets[symbol.id] = sanitized
        } else {
            priceAlertTargets.removeValue(forKey: symbol.id)
        }
    }

    func setPriceTargetsEnabled(for symbol: StockSymbol, enabled: Bool) {
        guard enabled else {
            priceAlertTargets.removeValue(forKey: symbol.id)
            return
        }
        guard let quote = quotes[symbol.id], quote.lastPrice > 0 else { return }
        updatePriceTargets(
            for: symbol,
            risingPrice: quote.lastPrice * (1 + risingThreshold / 100),
            fallingPrice: quote.lastPrice * (1 - fallingThreshold / 100)
        )
    }

    @discardableResult
    func generatePriceTargetsFromCurrentQuotes() -> Int {
        var generated = 0
        for symbol in symbols {
            guard let quote = quotes[symbol.id], quote.lastPrice > 0 else { continue }
            priceAlertTargets[symbol.id] = PriceAlertTargets(
                risingPrice: quote.lastPrice * (1 + risingThreshold / 100),
                fallingPrice: quote.lastPrice * (1 - fallingThreshold / 100)
            )
            generated += 1
        }
        return generated
    }

    func testAlert(_ direction: ThresholdDirection) {
        let symbol = symbols.first ?? StockSymbol.initialSymbols[0]
        let quote = quotes[symbol.id]
        let targets = priceAlertTargets[symbol.id]
        let targetPrice = direction == .rising
            ? targets?.risingPrice
            : targets?.fallingPrice
        presentAlert(
            ThresholdAlert(
                symbol: symbol,
                percent: direction == .rising ? risingThreshold : -fallingThreshold,
                lastPrice: quote?.lastPrice ?? targetPrice ?? 0,
                targetPrice: alertBasis == .targetPrice ? targetPrice : nil,
                basis: alertBasis,
                direction: direction,
                triggeredAt: Date()
            )
        )
    }

    private func evaluateThreshold(for quote: StockQuote) {
        guard alertsEnabled else { return }
        var gate = thresholdGates[quote.id] ?? ThresholdGate()
        let target: Double?
        let direction: ThresholdDirection?
        switch alertBasis {
        case .percentage:
            target = nil
            direction = gate.evaluate(
                percent: quote.changePercent,
                risingThreshold: risingThreshold,
                fallingThreshold: fallingThreshold
            )
        case .targetPrice:
            guard let targets = priceAlertTargets[quote.id], targets.isEnabled else {
                thresholdGates.removeValue(forKey: quote.id)
                return
            }
            direction = gate.evaluatePrice(
                price: quote.lastPrice,
                risingTarget: targets.risingPrice,
                fallingTarget: targets.fallingPrice
            )
            switch direction {
            case .rising: target = targets.risingPrice
            case .falling: target = targets.fallingPrice
            case nil: target = nil
            }
        }
        thresholdGates[quote.id] = gate
        guard let direction else { return }

        presentAlert(
            ThresholdAlert(
                symbol: quote.symbol,
                percent: quote.changePercent,
                lastPrice: quote.lastPrice,
                targetPrice: target,
                basis: alertBasis,
                direction: direction,
                triggeredAt: Date()
            )
        )
    }

    private func presentAlert(_ alert: ThresholdAlert) {
        activeAlert = alert
        playAlertSound(for: alert.direction)
        dismissAlertTask?.cancel()
        dismissAlertTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.activeAlert = nil
        }
    }

    private func playAlertSound(for direction: ThresholdDirection) {
        let isEnabled = direction == .rising ? bullSoundEnabled : bearSoundEnabled
        guard isEnabled else { return }

        let resourceName = direction == .rising ? "bull-moo" : "bear-growl"
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "wav") else {
            NSSound.beep()
            return
        }
        currentAlertSound?.stop()
        currentAlertSound = NSSound(contentsOf: url, byReference: true)
        currentAlertSound?.volume = 0.82
        currentAlertSound?.play()
    }

    private func restartRefreshLoop() {
        guard hasStarted else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshAll()
            while !Task.isCancelled {
                let seconds = self.refreshInterval
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { break }
                await self.refreshAll()
            }
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(symbols) {
            defaults.set(data, forKey: Keys.symbols)
        }
        defaults.set(lineOpacity, forKey: Keys.lineOpacity)
        defaults.set(chartWidth, forKey: Keys.chartWidth)
        defaults.set(labelOpacity, forKey: Keys.labelOpacity)
        defaults.set(fontScale, forKey: Keys.fontScale)
        defaults.set(showStockMeta, forKey: Keys.showStockMeta)
        defaults.set(backgroundOpacity, forKey: Keys.backgroundOpacity)
        defaults.set(risingThreshold, forKey: Keys.risingThreshold)
        defaults.set(fallingThreshold, forKey: Keys.fallingThreshold)
        defaults.set(alertBasis.rawValue, forKey: Keys.alertBasis)
        if let data = try? JSONEncoder().encode(priceAlertTargets) {
            defaults.set(data, forKey: Keys.priceAlertTargets)
        }
        defaults.set(refreshInterval, forKey: Keys.refreshInterval)
        defaults.set(clickThrough, forKey: Keys.clickThrough)
        defaults.set(alwaysOnTop, forKey: Keys.alwaysOnTop)
        defaults.set(compactMode, forKey: Keys.compactMode)
        defaults.set(displayScale, forKey: Keys.displayScale)
        defaults.set(bullSoundEnabled, forKey: Keys.bullSoundEnabled)
        defaults.set(bearSoundEnabled, forKey: Keys.bearSoundEnabled)
        defaults.set(alertsEnabled, forKey: Keys.alertsEnabled)
        defaults.set(alertOpacity, forKey: Keys.alertOpacity)
        defaults.set(shortcutEnabled, forKey: Keys.shortcutEnabled)
        defaults.set(shortcutModifier.rawValue, forKey: Keys.shortcutModifier)
        defaults.set(shortcutKey.rawValue, forKey: Keys.shortcutKey)
    }

    private func notifyShortcutChanged() {
        NotificationCenter.default.post(name: .stockPetShortcutChanged, object: nil)
    }

    private enum FetchOutcome: Sendable {
        case success(StockQuote)
        case failure(String, String)
    }

    private enum Keys {
        static let symbols = "stockPet.symbols"
        static let lineOpacity = "stockPet.lineOpacity"
        static let chartWidth = "stockPet.chartWidth"
        static let labelOpacity = "stockPet.labelOpacity"
        static let fontScale = "stockPet.fontScale"
        static let showStockMeta = "stockPet.showStockMeta"
        static let backgroundOpacity = "stockPet.backgroundOpacity"
        static let risingThreshold = "stockPet.risingThreshold"
        static let fallingThreshold = "stockPet.fallingThreshold"
        static let alertBasis = "stockPet.alertBasis"
        static let priceAlertTargets = "stockPet.priceAlertTargets"
        static let refreshInterval = "stockPet.refreshInterval"
        static let clickThrough = "stockPet.clickThrough"
        static let alwaysOnTop = "stockPet.alwaysOnTop"
        static let compactMode = "stockPet.compactMode"
        static let displayScale = "stockPet.displayScale"
        static let bullSoundEnabled = "stockPet.bullSoundEnabled"
        static let bearSoundEnabled = "stockPet.bearSoundEnabled"
        static let alertsEnabled = "stockPet.alertsEnabled"
        static let alertOpacity = "stockPet.alertOpacity"
        static let shortcutEnabled = "stockPet.shortcutEnabled"
        static let shortcutModifier = "stockPet.shortcutModifier"
        static let shortcutKey = "stockPet.shortcutKey"
    }
}
