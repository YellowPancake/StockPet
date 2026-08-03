import Foundation

protocol QuoteProviding: Sendable {
    func search(query: String) async throws -> [StockSymbol]
    func fetchIntraday(for symbol: StockSymbol) async throws -> StockQuote
    func fetchLatestQuotes(for symbols: [StockSymbol]) async throws -> [LatestQuoteUpdate]
}

actor MarketQuoteService: QuoteProviding {
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let searchToken = "D43BF722C8E33DA55D5C6812C6C46"

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 20
            configuration.waitsForConnectivity = false
            configuration.connectionProxyDictionary = [:]
            self.session = URLSession(configuration: configuration)
        }
    }

    func search(query: String) async throws -> [StockSymbol] {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanQuery.isEmpty else { return [] }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "searchapi.eastmoney.com"
        components.path = "/api/suggest/get"
        components.queryItems = [
            URLQueryItem(name: "input", value: cleanQuery),
            URLQueryItem(name: "type", value: "14"),
            URLQueryItem(name: "token", value: searchToken),
            URLQueryItem(name: "count", value: "20")
        ]
        guard let url = components.url else { throw QuoteServiceError.invalidURL }

        let data = try await request(url)
        let response = try decoder.decode(SearchEnvelope.self, from: data)
        guard response.table.status == 0 else {
            throw QuoteServiceError.server(tr("搜索服务暂不可用"))
        }

        var seen = Set<String>()
        return response.table.data.compactMap { item in
            guard let market = Self.market(for: item) else { return nil }
            let quoteID = item.quoteID.isEmpty ? "\(item.marketNumber).\(item.code)" : item.quoteID
            guard seen.insert(quoteID).inserted else { return nil }
            return StockSymbol(
                code: item.code,
                name: localizedStockName(item.name, code: item.code),
                market: market,
                quoteID: quoteID
            )
        }
    }

    func fetchIntraday(for symbol: StockSymbol) async throws -> StockQuote {
        do {
            return try await fetchTencentIntraday(for: symbol)
        } catch {
            return try await fetchEastmoneyIntraday(for: symbol)
        }
    }

    func fetchLatestQuotes(for symbols: [StockSymbol]) async throws -> [LatestQuoteUpdate] {
        guard !symbols.isEmpty else { return [] }

        var updates: [LatestQuoteUpdate] = []
        var lastError: Error?
        for start in stride(from: 0, to: symbols.count, by: 40) {
            let end = min(start + 40, symbols.count)
            let batch = Array(symbols[start..<end])
            do {
                updates.append(contentsOf: try await fetchTencentLatestBatch(batch))
            } catch {
                lastError = error
            }
        }
        if updates.isEmpty, let lastError {
            throw lastError
        }
        return updates
    }

    private func fetchTencentLatestBatch(
        _ symbols: [StockSymbol]
    ) async throws -> [LatestQuoteUpdate] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "qt.gtimg.cn"
        components.path = "/q"
        components.queryItems = [
            URLQueryItem(
                name: "q",
                value: symbols.map(Self.tencentRealtimeCode(for:)).joined(separator: ",")
            ),
            URLQueryItem(name: "_", value: String(Int(Date().timeIntervalSince1970 * 1_000)))
        ]
        guard let url = components.url else { throw QuoteServiceError.invalidURL }

        let data = try await request(url, timeout: 2)
        // The payload is GBK, but every field used here is ASCII. Lossy UTF-8
        // decoding keeps delimiters and numeric values intact without shipping a
        // separate encoding dependency.
        let text = String(decoding: data, as: UTF8.self)
        let parsed = Self.parseTencentRealtime(text, symbols: symbols)
        guard !parsed.isEmpty else { throw QuoteServiceError.invalidResponse }
        return parsed
    }

    private func fetchEastmoneyIntraday(for symbol: StockSymbol) async throws -> StockQuote {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "push2delay.eastmoney.com"
        components.path = "/api/qt/stock/trends2/get"
        components.queryItems = [
            URLQueryItem(name: "secid", value: symbol.quoteID),
            URLQueryItem(name: "fields1", value: "f1,f2,f3,f4,f5,f6,f7,f8,f9,f10,f11,f12,f13"),
            URLQueryItem(name: "fields2", value: "f51,f52,f53,f54,f55,f56,f57,f58"),
            URLQueryItem(name: "iscr", value: "0"),
            URLQueryItem(name: "ndays", value: "1")
        ]
        guard let url = components.url else { throw QuoteServiceError.invalidURL }

        let data = try await request(url)
        let response = try decoder.decode(TrendEnvelope.self, from: data)
        guard response.returnCode == 0, let payload = response.data else {
            throw QuoteServiceError.server(tr("行情服务暂不可用"))
        }

        let points = payload.trends.compactMap(Self.parseTrend)
        guard Self.hasDrawableIntradayData(points),
              let first = points.first,
              let last = points.last
        else {
            throw QuoteServiceError.noIntradayData
        }

        let dayOpen = first.open > 0 ? first.open : first.close
        let previousClose = payload.previousClose > 0 ? payload.previousClose : dayOpen
        return StockQuote(
            symbol: symbol,
            points: points,
            dayOpen: dayOpen,
            previousClose: previousClose,
            lastPrice: last.close,
            updatedAt: last.time,
            isStale: false,
            statusMessage: nil
        )
    }

    private func fetchTencentIntraday(for symbol: StockSymbol) async throws -> StockQuote {
        let tencentCode = Self.tencentCode(for: symbol)
        var components = URLComponents()
        components.scheme = "https"
        components.host = "web.ifzq.gtimg.cn"
        components.path = "/appstock/app/minute/query"
        components.queryItems = [URLQueryItem(name: "code", value: tencentCode)]
        guard let url = components.url else { throw QuoteServiceError.invalidURL }

        let data = try await request(url)
        let response = try decoder.decode(TencentEnvelope.self, from: data)
        guard response.code == 0,
              let payload = response.data[tencentCode],
              let quoteFields = payload.quotes[tencentCode],
              quoteFields.count > 5
        else {
            throw QuoteServiceError.invalidResponse
        }

        let date = payload.minute.date.isEmpty
            ? Self.datePrefix(from: quoteFields[safe: 30] ?? "")
            : payload.minute.date
        let points = payload.minute.values.compactMap {
            Self.parseTencentMinute($0, date: date, market: symbol.market)
        }
        guard Self.hasDrawableIntradayData(points),
              let last = points.last
        else {
            throw QuoteServiceError.noIntradayData
        }

        let dayOpen = Double(quoteFields[5]).flatMap { $0 > 0 ? $0 : nil }
            ?? points.first?.close
            ?? last.close
        let previousClose = Double(quoteFields[4]).flatMap { $0 > 0 ? $0 : nil }
            ?? dayOpen
        let latestPrice = Double(quoteFields[3]).flatMap { $0 > 0 ? $0 : nil }
            ?? last.close

        return StockQuote(
            symbol: symbol,
            points: points,
            dayOpen: dayOpen,
            previousClose: previousClose,
            lastPrice: latestPrice,
            updatedAt: last.time,
            isStale: false,
            statusMessage: nil
        )
    }

    private func request(_ url: URL, timeout: TimeInterval = 15) async throws -> Data {
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: timeout
        )
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("https://quote.eastmoney.com/", forHTTPHeaderField: "Referer")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw QuoteServiceError.invalidResponse
        }
        return data
    }

    static func market(for item: SearchItem) -> StockMarket? {
        let classification = item.classification.lowercased()
        if classification == "astock" || ["0", "1"].contains(item.marketNumber) {
            return .aShare
        }
        if classification == "hk" || item.marketNumber == "116" {
            return .hongKong
        }
        if classification == "usstock" || ["105", "106", "107"].contains(item.marketNumber) {
            return .unitedStates
        }
        return nil
    }

    static func hasDrawableIntradayData(_ points: [IntradayPoint]) -> Bool {
        points.count >= 2
    }

    static func parseTrend(_ raw: String) -> IntradayPoint? {
        let values = raw.split(separator: ",", omittingEmptySubsequences: false)
        guard values.count >= 5,
              let date = Self.trendDateFormatter.date(from: String(values[0])),
              let open = Double(values[1]),
              let close = Double(values[2]),
              let high = Double(values[3]),
              let low = Double(values[4]),
              close > 0
        else {
            return nil
        }
        return IntradayPoint(time: date, open: open, close: close, high: high, low: low)
    }

    static func tencentCode(for symbol: StockSymbol) -> String {
        switch symbol.market {
        case .aShare:
            if symbol.code.hasPrefix("6") {
                return "sh\(symbol.code)"
            }
            if symbol.code.hasPrefix("4") || symbol.code.hasPrefix("8") || symbol.code.hasPrefix("9") {
                return "bj\(symbol.code)"
            }
            return "sz\(symbol.code)"
        case .hongKong:
            return "hk\(symbol.code)"
        case .unitedStates:
            return "us\(symbol.code.uppercased())"
        }
    }

    static func tencentRealtimeCode(for symbol: StockSymbol) -> String {
        switch symbol.market {
        case .hongKong:
            // Without r_ Tencent may return the free 15-minute delayed HK quote.
            return "r_hk\(symbol.code)"
        case .aShare, .unitedStates:
            return tencentCode(for: symbol)
        }
    }

    static func parseTencentRealtime(
        _ raw: String,
        symbols: [StockSymbol]
    ) -> [LatestQuoteUpdate] {
        let byCode = Dictionary(
            uniqueKeysWithValues: symbols.map { (tencentRealtimeCode(for: $0), $0) }
        )

        return raw
            .split(separator: ";", omittingEmptySubsequences: true)
            .compactMap { row in
                guard let equals = row.firstIndex(of: "=") else { return nil }
                let variable = row[..<equals]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard variable.hasPrefix("v_") else { return nil }
                let realtimeCode = String(variable.dropFirst(2))
                guard let symbol = byCode[realtimeCode] else { return nil }

                let fields = row.split(separator: "~", omittingEmptySubsequences: false)
                guard fields.count > 30,
                      let lastPrice = Double(fields[3]), lastPrice > 0,
                      let previousClose = Double(fields[4]), previousClose > 0,
                      let updatedAt = realtimeDate(
                        String(fields[30]).trimmingCharacters(in: CharacterSet(charactersIn: "\"")),
                        market: symbol.market
                      )
                else {
                    return nil
                }
                return LatestQuoteUpdate(
                    symbol: symbol,
                    lastPrice: lastPrice,
                    previousClose: previousClose,
                    updatedAt: updatedAt
                )
            }
    }

    private static func realtimeDate(_ raw: String, market: StockMarket) -> Date? {
        switch market {
        case .aShare:
            return aShareRealtimeDateFormatter.date(from: raw)
        case .hongKong:
            return hongKongRealtimeDateFormatter.date(from: raw)
        case .unitedStates:
            return unitedStatesRealtimeDateFormatter.date(from: raw)
        }
    }

    static func parseTencentMinute(
        _ raw: String,
        date: String,
        market: StockMarket
    ) -> IntradayPoint? {
        let values = raw.split(separator: " ", omittingEmptySubsequences: true)
        guard values.count >= 2,
              values[0].count == 4,
              let price = Double(values[1]),
              price > 0
        else {
            return nil
        }

        let normalizedDate: String
        if date.count == 8, !date.contains("-") {
            normalizedDate = "\(date.prefix(4))-\(date.dropFirst(4).prefix(2))-\(date.suffix(2))"
        } else if date.count >= 10 {
            normalizedDate = String(date.prefix(10)).replacingOccurrences(of: "/", with: "-")
        } else {
            normalizedDate = Self.fallbackDateFormatter.string(from: Date())
        }

        let time = "\(values[0].prefix(2)):\(values[0].suffix(2))"
        let formatter = market == .unitedStates
            ? Self.usMinuteDateFormatter
            : Self.asiaMinuteDateFormatter
        guard let parsedDate = formatter.date(from: "\(normalizedDate) \(time)") else {
            return nil
        }
        return IntradayPoint(time: parsedDate, open: price, close: price, high: price, low: price)
    }

    private static func datePrefix(from raw: String) -> String {
        guard raw.count >= 10 else { return "" }
        return String(raw.prefix(10))
    }

    private static let trendDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private static let asiaMinuteDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private static let usMinuteDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    private static let fallbackDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let aShareRealtimeDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter
    }()

    private static let hongKongRealtimeDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Hong_Kong")
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return formatter
    }()

    private static let unitedStatesRealtimeDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

struct SearchEnvelope: Decodable {
    let table: SearchTable

    enum CodingKeys: String, CodingKey {
        case table = "QuotationCodeTable"
    }
}

struct SearchTable: Decodable {
    let data: [SearchItem]
    let status: Int
    let message: String

    enum CodingKeys: String, CodingKey {
        case data = "Data"
        case status = "Status"
        case message = "Message"
    }
}

struct SearchItem: Decodable {
    let code: String
    let name: String
    let classification: String
    let marketNumber: String
    let quoteID: String

    enum CodingKeys: String, CodingKey {
        case code = "Code"
        case name = "Name"
        case classification = "Classify"
        case marketNumber = "MktNum"
        case quoteID = "QuoteID"
    }
}

struct TrendEnvelope: Decodable {
    let returnCode: Int
    let data: TrendPayload?

    enum CodingKeys: String, CodingKey {
        case returnCode = "rc"
        case data
    }
}

struct TrendPayload: Decodable {
    let previousClose: Double
    let trends: [String]

    enum CodingKeys: String, CodingKey {
        case previousClose = "preClose"
        case trends
    }
}

struct TencentEnvelope: Decodable {
    let code: Int
    let data: [String: TencentPayload]
}

struct TencentPayload: Decodable {
    let minute: TencentMinutePayload
    let quotes: [String: [String]]

    enum CodingKeys: String, CodingKey {
        case minute = "data"
        case quotes = "qt"
    }
}

struct TencentMinutePayload: Decodable {
    let values: [String]
    let date: String

    enum CodingKeys: String, CodingKey {
        case values = "data"
        case date
    }
}
