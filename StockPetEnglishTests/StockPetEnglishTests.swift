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
        XCTAssertEqual(tr("涨跌显示"), "Change display")
        XCTAssertEqual(tr("百分比"), "Percentage")
        XCTAssertEqual(tr("涨跌额"), "Price change")
        XCTAssertEqual(tr("显示股票代码与市场"), "Show ticker and market")
        XCTAssertEqual(tr("5 秒"), "5 seconds")
        XCTAssertEqual(tr("1 秒（极速）"), "1 second (Fast)")
        XCTAssertEqual(tr("软件更新"), "Software Update")
        XCTAssertEqual(tr("路线一"), "Route 1")
        XCTAssertEqual(tr("路线二"), "Route 2")
        XCTAssertEqual(
            tr("检查是否有新版本，并下载适用于当前系统和语言的安装包。"),
            "Check whether a new version is available and download the package for this system and language."
        )
    }
}
