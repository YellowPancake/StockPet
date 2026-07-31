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

    func testTencentCodeMappingForThreeMarkets() {
        XCTAssertEqual(MarketQuoteService.tencentCode(for: StockSymbol.initialSymbols[0]), "sh600519")
        XCTAssertEqual(MarketQuoteService.tencentCode(for: StockSymbol.initialSymbols[1]), "hk00700")
        XCTAssertEqual(MarketQuoteService.tencentCode(for: StockSymbol.initialSymbols[2]), "usAAPL")
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
}

private struct AlwaysFailingQuoteService: QuoteProviding {
    func search(query: String) async throws -> [StockSymbol] {
        []
    }

    func fetchIntraday(for symbol: StockSymbol) async throws -> StockQuote {
        throw URLError(.notConnectedToInternet)
    }
}
