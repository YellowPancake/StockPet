import XCTest
@testable import StockPet

final class StockPetTests: XCTestCase {
    func testMarketColorConventionIsReversedForUnitedStates() {
        XCTAssertEqual(StockMarket.aShare.colorRole(isRising: true), .red)
        XCTAssertEqual(StockMarket.hongKong.colorRole(isRising: true), .red)
        XCTAssertEqual(StockMarket.unitedStates.colorRole(isRising: true), .green)
        XCTAssertEqual(StockMarket.aShare.colorRole(isRising: false), .green)
        XCTAssertEqual(StockMarket.unitedStates.colorRole(isRising: false), .red)
    }

    func testQuoteProvidesPercentageAndAbsoluteChange() {
        let quote = StockQuote(
            symbol: StockSymbol.initialSymbols[0],
            points: [],
            dayOpen: 100,
            previousClose: 100,
            lastPrice: 103.25,
            updatedAt: Date(),
            isStale: false,
            statusMessage: nil
        )
        XCTAssertEqual(quote.changePercent, 3.25, accuracy: 0.0001)
        XCTAssertEqual(quote.changeAmount, 3.25, accuracy: 0.0001)
    }

    func testParsesActualEastmoneyTrendFormat() throws {
        // 真实 trends2 接口字段布局：时间、开、收、高、低、量、额、均价。
        let raw = "2026-07-30 09:31,1323.00,1329.50,1330.00,1322.00,753,99792267.00,1324.911"
        let point = try XCTUnwrap(MarketQuoteService.parseTrend(raw))

        XCTAssertEqual(point.open, 1323.00, accuracy: 0.001)
        XCTAssertEqual(point.close, 1329.50, accuracy: 0.001)
        XCTAssertEqual(point.high, 1330.00, accuracy: 0.001)
        XCTAssertEqual(point.low, 1322.00, accuracy: 0.001)
    }

    func testParsesActualTencentMinuteFormat() throws {
        let point = try XCTUnwrap(
            MarketQuoteService.parseTencentMinute(
                "0931 1329.50 961 127323916.11",
                date: "20260730",
                market: .aShare
            )
        )

        XCTAssertEqual(point.close, 1329.50, accuracy: 0.001)
    }

    func testSingleTencentPointFallsBackInsteadOfProducingAnEmptyChart() throws {
        let point = try XCTUnwrap(
            MarketQuoteService.parseTencentMinute(
                "1600 333.43 74817792",
                date: "2026-07-30",
                market: .unitedStates
            )
        )

        XCTAssertFalse(MarketQuoteService.hasDrawableIntradayData([point]))
        XCTAssertTrue(MarketQuoteService.hasDrawableIntradayData([point, point]))
    }

    func testTencentCodeMappingForThreeMarkets() {
        XCTAssertEqual(MarketQuoteService.tencentCode(for: StockSymbol.initialSymbols[0]), "sh600519")
        XCTAssertEqual(MarketQuoteService.tencentCode(for: StockSymbol.initialSymbols[1]), "hk00700")
        XCTAssertEqual(MarketQuoteService.tencentCode(for: StockSymbol.initialSymbols[2]), "usAAPL")
        XCTAssertEqual(
            MarketQuoteService.tencentRealtimeCode(for: StockSymbol.initialSymbols[1]),
            "r_hk00700"
        )
    }

    func testParsesTencentBatchRealtimeQuote() throws {
        var fields = Array(repeating: "", count: 31)
        fields[0] = "1"
        fields[1] = "Kweichow Moutai"
        fields[2] = "600519"
        fields[3] = "1355.70"
        fields[4] = "1350.00"
        fields[30] = "20260803145240"
        let raw = "v_sh600519=\"\(fields.joined(separator: "~"))\";"

        let update = try XCTUnwrap(
            MarketQuoteService.parseTencentRealtime(
                raw,
                symbols: [StockSymbol.initialSymbols[0]]
            ).first
        )
        XCTAssertEqual(update.lastPrice, 1355.70, accuracy: 0.001)
        XCTAssertEqual(update.previousClose, 1350.00, accuracy: 0.001)
    }

    func testTencentBatchToleratesDuplicateLegacySymbols() {
        let symbol = StockSymbol.initialSymbols[0]
        let duplicate = StockSymbol(
            code: symbol.code,
            name: "Duplicate",
            market: symbol.market,
            quoteID: "legacy.\(symbol.code)"
        )
        XCTAssertNoThrow(
            MarketQuoteService.parseTencentRealtime("", symbols: [symbol, duplicate])
        )
    }

    func testMarketSessionsUseTheirOwnTimeZones() throws {
        let formatter = ISO8601DateFormatter()
        let aShareMorning = try XCTUnwrap(formatter.date(from: "2026-08-03T02:00:00Z"))
        let aShareLunch = try XCTUnwrap(formatter.date(from: "2026-08-03T04:00:00Z"))
        let usSession = try XCTUnwrap(formatter.date(from: "2026-08-03T15:00:00Z"))

        XCTAssertTrue(StockMarket.aShare.isLikelyTrading(at: aShareMorning))
        XCTAssertFalse(StockMarket.aShare.isLikelyTrading(at: aShareLunch))
        XCTAssertTrue(StockMarket.unitedStates.isLikelyTrading(at: usSession))
    }

    func testSoftwareUpdateVersionComparison() {
        XCTAssertTrue(SoftwareUpdateService.isVersion("0.4.0", newerThan: "0.3.0"))
        XCTAssertTrue(SoftwareUpdateService.isVersion("v1.0.0", newerThan: "0.9.9"))
        XCTAssertFalse(SoftwareUpdateService.isVersion("0.4.0", newerThan: "0.4.0"))
        XCTAssertFalse(SoftwareUpdateService.isVersion("0.3.9", newerThan: "0.4.0"))
    }

    func testSoftwareUpdateDigestParsesExactReleaseAsset() {
        let expected = String(repeating: "ab", count: 32)
        let notes = """
        StockPet v0.4.1
        SHA256 (StockPet-macOS-Chinese.zip): \(expected.uppercased())
        SHA256 (StockPet-Windows-x64-Chinese.zip): \(String(repeating: "cd", count: 32))
        """
        XCTAssertEqual(
            SoftwareUpdateService.digest(for: "StockPet-macOS-Chinese.zip", in: notes),
            "sha256:\(expected)"
        )
        XCTAssertNil(SoftwareUpdateService.digest(for: "StockPet-macOS-English.zip", in: notes))
    }

    func testSearchMarketsMapToSupportedRegions() {
        let aShare = SearchItem(
            code: "600519",
            name: "贵州茅台",
            classification: "AStock",
            marketNumber: "1",
            quoteID: "1.600519"
        )
        let hongKong = SearchItem(
            code: "00700",
            name: "腾讯控股",
            classification: "HK",
            marketNumber: "116",
            quoteID: "116.00700"
        )
        let unitedStates = SearchItem(
            code: "AAPL",
            name: "苹果",
            classification: "UsStock",
            marketNumber: "105",
            quoteID: "105.AAPL"
        )

        XCTAssertEqual(MarketQuoteService.market(for: aShare), .aShare)
        XCTAssertEqual(MarketQuoteService.market(for: hongKong), .hongKong)
        XCTAssertEqual(MarketQuoteService.market(for: unitedStates), .unitedStates)
    }

    func testThresholdGateOnlyRealertsAfterReturningInside() {
        var gate = ThresholdGate()

        XCTAssertEqual(
            gate.evaluate(percent: 3.1, risingThreshold: 3, fallingThreshold: 3),
            .rising
        )
        XCTAssertNil(gate.evaluate(percent: 3.8, risingThreshold: 3, fallingThreshold: 3))
        XCTAssertNil(gate.evaluate(percent: 2.95, risingThreshold: 3, fallingThreshold: 3))
        XCTAssertNil(gate.evaluate(percent: 2.7, risingThreshold: 3, fallingThreshold: 3))
        XCTAssertEqual(
            gate.evaluate(percent: 3.2, risingThreshold: 3, fallingThreshold: 3),
            .rising
        )
    }

    func testTargetPriceGateUsesRelativeHysteresisBeforeRearming() {
        var gate = ThresholdGate()

        XCTAssertEqual(
            gate.evaluatePrice(price: 103.0, risingTarget: 103, fallingTarget: 97),
            .rising
        )
        XCTAssertNil(
            gate.evaluatePrice(price: 102.9, risingTarget: 103, fallingTarget: 97)
        )
        XCTAssertNil(
            gate.evaluatePrice(price: 102.8, risingTarget: 103, fallingTarget: 97)
        )
        XCTAssertEqual(
            gate.evaluatePrice(price: 103.1, risingTarget: 103, fallingTarget: 97),
            .rising
        )
        XCTAssertEqual(
            gate.evaluatePrice(price: 96.9, risingTarget: 103, fallingTarget: 97),
            .falling
        )
    }

    @MainActor
    func testStoreAcceptsMoreThanTenSymbols() {
        let suiteName = "StockPetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = StockStore(service: AlwaysFailingQuoteService(), defaults: defaults)

        for index in 0..<12 {
            let symbol = StockSymbol(
                code: "TEST\(index)",
                name: "测试\(index)",
                market: .unitedStates,
                quoteID: "105.TEST\(index)"
            )
            XCTAssertNil(store.add(symbol))
        }

        XCTAssertGreaterThan(store.symbols.count, 10)
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testAnimalAlertSoundsAreBundled() {
        XCTAssertNotNil(Bundle.main.url(forResource: "bull-moo", withExtension: "wav"))
        XCTAssertNotNil(Bundle.main.url(forResource: "bear-growl", withExtension: "wav"))
    }

    @MainActor
    func testAppearanceDefaultsHideStockCodeAndMarket() {
        let suiteName = "StockPetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = StockStore(service: AlwaysFailingQuoteService(), defaults: defaults)

        XCTAssertFalse(store.showStockMeta)
        XCTAssertEqual(store.changeDisplayMode, .percentage)
        XCTAssertEqual(store.fontScale, 1.0)
        XCTAssertEqual(store.chartWidth, 310)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @MainActor
    func testCorruptAppearancePreferencesAreClampedAtStartup() {
        let suiteName = "StockPetTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(Double.infinity, forKey: "stockPet.displayScale")
        defaults.set(-500.0, forKey: "stockPet.chartWidth")
        defaults.set(50.0, forKey: "stockPet.backgroundOpacity")

        let store = StockStore(service: AlwaysFailingQuoteService(), defaults: defaults)

        XCTAssertEqual(store.displayScale, 1)
        XCTAssertEqual(store.chartWidth, 160)
        XCTAssertEqual(store.backgroundOpacity, 0.55)
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private struct AlwaysFailingQuoteService: QuoteProviding {
    func search(query: String) async throws -> [StockSymbol] {
        []
    }

    func fetchIntraday(for symbol: StockSymbol) async throws -> StockQuote {
        throw URLError(.notConnectedToInternet)
    }

    func fetchLatestQuotes(for symbols: [StockSymbol]) async throws -> [LatestQuoteUpdate] {
        throw URLError(.notConnectedToInternet)
    }
}
