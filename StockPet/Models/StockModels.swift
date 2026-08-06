import Foundation

enum StockMarket: String, Codable, CaseIterable, Sendable {
    case aShare
    case hongKong
    case unitedStates

    var displayName: String {
        switch self {
        case .aShare: tr("A股")
        case .hongKong: tr("港股")
        case .unitedStates: tr("美股")
        }
    }

    var currencySymbol: String {
        switch self {
        case .aShare: "¥"
        case .hongKong: "HK$"
        case .unitedStates: "$"
        }
    }

    /// 中国内地和香港采用红涨绿跌，美股采用绿涨红跌。
    func colorRole(isRising: Bool) -> MarketColorRole {
        switch self {
        case .aShare, .hongKong:
            isRising ? .red : .green
        case .unitedStates:
            isRising ? .green : .red
        }
    }

    func isLikelyTrading(at date: Date = Date()) -> Bool {
        let timeZoneIdentifier: String
        switch self {
        case .aShare: timeZoneIdentifier = "Asia/Shanghai"
        case .hongKong: timeZoneIdentifier = "Asia/Hong_Kong"
        case .unitedStates: timeZoneIdentifier = "America/New_York"
        }
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else { return true }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = components.weekday,
              (2...6).contains(weekday),
              let hour = components.hour,
              let minute = components.minute
        else {
            return false
        }
        let minutes = hour * 60 + minute
        switch self {
        case .aShare:
            return (570...690).contains(minutes) || (780...900).contains(minutes)
        case .hongKong:
            return (570...720).contains(minutes) || (780...960).contains(minutes)
        case .unitedStates:
            return (570...960).contains(minutes)
        }
    }
}

enum MarketColorRole: String, Equatable, Sendable {
    case red
    case green
}

enum InstrumentType: String, Codable, Sendable {
    case stock
    case index
}

struct StockSymbol: Identifiable, Codable, Hashable, Sendable {
    var id: String { quoteID }

    let code: String
    let name: String
    let market: StockMarket
    let quoteID: String
    let instrumentType: InstrumentType?

    init(
        code: String,
        name: String,
        market: StockMarket,
        quoteID: String,
        instrumentType: InstrumentType? = nil
    ) {
        self.code = code
        self.name = name
        self.market = market
        self.quoteID = quoteID
        self.instrumentType = instrumentType
    }

    var isIndex: Bool {
        if instrumentType == .index { return true }
        let marketNumber = quoteID.split(separator: ".", maxSplits: 1).first.map(String.init)
        switch market {
        case .aShare:
            return (marketNumber == "1" && code.hasPrefix("000")) ||
                (marketNumber == "0" && (code.hasPrefix("399") || code == "899050"))
        case .hongKong:
            return marketNumber == "100" || marketNumber == "124"
        case .unitedStates:
            return marketNumber == "100"
        }
    }

    var displayMarketName: String {
        guard isIndex else { return market.displayName }
        switch market {
        case .aShare: return tr("A股指数")
        case .hongKong: return tr("港股指数")
        case .unitedStates: return tr("美股指数")
        }
    }

    static let initialSymbols: [StockSymbol] = [
        StockSymbol(
            code: "600519",
            name: localizedStockName("贵州茅台", code: "600519"),
            market: .aShare,
            quoteID: "1.600519"
        ),
        StockSymbol(
            code: "00700",
            name: localizedStockName("腾讯控股", code: "00700"),
            market: .hongKong,
            quoteID: "116.00700"
        ),
        StockSymbol(
            code: "AAPL",
            name: localizedStockName("苹果", code: "AAPL"),
            market: .unitedStates,
            quoteID: "105.AAPL"
        )
    ]
}

struct IntradayPoint: Identifiable, Hashable, Sendable {
    var id: Date { time }

    let time: Date
    let open: Double
    let close: Double
    let high: Double
    let low: Double
}

struct StockQuote: Identifiable, Sendable {
    var id: String { symbol.id }

    let symbol: StockSymbol
    let points: [IntradayPoint]
    let dayOpen: Double
    let previousClose: Double
    let lastPrice: Double
    let updatedAt: Date
    var isStale: Bool
    var statusMessage: String?

    var changePercent: Double {
        guard previousClose > 0 else { return 0 }
        return (lastPrice - previousClose) / previousClose * 100
    }

    var changeAmount: Double {
        lastPrice - previousClose
    }
}

struct LatestQuoteUpdate: Sendable {
    let symbol: StockSymbol
    let lastPrice: Double
    let previousClose: Double
    let updatedAt: Date
}

enum ThresholdDirection: String, Sendable {
    case rising
    case falling
}

enum AlertBasis: String, Codable, CaseIterable, Identifiable, Sendable {
    case percentage
    case targetPrice

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .percentage: tr("昨收涨跌幅")
        case .targetPrice: tr("目标价格")
        }
    }
}

enum ChangeDisplayMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case percentage
    case amount

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .percentage: tr("百分比")
        case .amount: tr("涨跌额")
        }
    }
}

struct PriceAlertTargets: Codable, Equatable, Sendable {
    var risingPrice: Double
    var fallingPrice: Double

    var isEnabled: Bool {
        risingPrice > 0 || fallingPrice > 0
    }
}

struct ThresholdAlert: Identifiable, Sendable {
    let id = UUID()
    let symbol: StockSymbol
    let percent: Double
    let lastPrice: Double
    let targetPrice: Double?
    let basis: AlertBasis
    let direction: ThresholdDirection
    let triggeredAt: Date
}

enum AlertArmState: String {
    case armed
    case risingTriggered
    case fallingTriggered
}

enum ShortcutModifierOption: String, Codable, CaseIterable, Identifiable {
    case commandOption
    case commandShift
    case controlOption
    case controlShift

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .commandOption: "⌘⌥"
        case .commandShift: "⌘⇧"
        case .controlOption: "⌃⌥"
        case .controlShift: "⌃⇧"
        }
    }
}

enum ShortcutKeyOption: String, Codable, CaseIterable, Identifiable {
    case s = "S"
    case p = "P"
    case h = "H"
    case k = "K"
    case d = "D"
    case f = "F"
    case space = "Space"

    var id: String { rawValue }
    var displayName: String { self == .space ? tr("空格") : rawValue }
}

extension Notification.Name {
    static let stockPetShortcutChanged = Notification.Name("stockPet.shortcutChanged")
    static let stockPetVisibilityScheduleChanged = Notification.Name("stockPet.visibilityScheduleChanged")
}

struct DailyVisibilitySchedule {
    static func normalizedMinutes(_ value: Int) -> Int {
        min(max(value, 0), 1_439)
    }

    static func shouldShow(nowMinutes: Int, showMinutes: Int, hideMinutes: Int) -> Bool? {
        let now = normalizedMinutes(nowMinutes)
        let show = normalizedMinutes(showMinutes)
        let hide = normalizedMinutes(hideMinutes)
        guard show != hide else { return nil }
        if show < hide {
            return now >= show && now < hide
        }
        return now >= show || now < hide
    }
}

struct ThresholdGate {
    private(set) var state: AlertArmState = .armed

    mutating func evaluate(
        percent: Double,
        risingThreshold: Double,
        fallingThreshold: Double,
        hysteresis: Double = 0.15
    ) -> ThresholdDirection? {
        if percent >= risingThreshold, state != .risingTriggered {
            state = .risingTriggered
            return .rising
        }
        if percent <= -fallingThreshold, state != .fallingTriggered {
            state = .fallingTriggered
            return .falling
        }
        if percent < risingThreshold - hysteresis,
           percent > -fallingThreshold + hysteresis {
            state = .armed
        }
        return nil
    }

    mutating func evaluatePrice(
        price: Double,
        risingTarget: Double,
        fallingTarget: Double,
        hysteresisRatio: Double = 0.0015
    ) -> ThresholdDirection? {
        if risingTarget > 0, price >= risingTarget, state != .risingTriggered {
            state = .risingTriggered
            return .rising
        }
        if fallingTarget > 0, price <= fallingTarget, state != .fallingTriggered {
            state = .fallingTriggered
            return .falling
        }

        let isBelowRisingRearm = risingTarget <= 0
            || price < risingTarget * (1 - hysteresisRatio)
        let isAboveFallingRearm = fallingTarget <= 0
            || price > fallingTarget * (1 + hysteresisRatio)
        if isBelowRisingRearm, isAboveFallingRearm {
            state = .armed
        }
        return nil
    }
}

enum QuoteServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unsupportedSymbol
    case noIntradayData
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            tr("行情地址无效")
        case .invalidResponse:
            tr("行情返回格式异常")
        case .unsupportedSymbol:
            tr("暂不支持这个股票或市场")
        case .noIntradayData:
            tr("今天暂无分时数据")
        case .server(let message):
            message
        }
    }
}
