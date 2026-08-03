import XCTest
@testable import StockPetEnglish

final class StockPetEnglishTests: XCTestCase {
    func testEnglishDefaultMarketsAndStocks() {
        XCTAssertEqual(StockMarket.aShare.displayName, "A-share")
        XCTAssertEqual(StockMarket.hongKong.displayName, "HK")
        XCTAssertEqual(StockMarket.unitedStates.displayName, "US")
        XCTAssertEqual(
            StockSymbol.initialSymbols.map(\.name),
            ["Kweichow Moutai", "Tencent Holdings", "Apple"]
        )
    }

    func testEnglishLocalizationResource() {
        XCTAssertEqual(tr("桌面股票"), "Watchlist")
        XCTAssertEqual(tr("牛熊提醒"), "Bull & Bear Alerts")
        XCTAssertEqual(tr("目标价格"), "Target price")
        XCTAssertEqual(tr("刷新实时价"), "Refresh live prices")
        XCTAssertEqual(tr("隐藏桌宠"), "Hide Stock Pet")
        XCTAssertEqual(tr("曲线宽度"), "Chart width")
        XCTAssertEqual(tr("字体大小"), "Font size")
        XCTAssertEqual(tr("显示股票代码与市场"), "Show ticker and market")
        XCTAssertEqual(tr("5 秒"), "5 seconds")
        XCTAssertEqual(tr("1 秒（极速）"), "1 second (Fast)")
        XCTAssertEqual(tr("软件更新"), "Software Update")
    }
}
