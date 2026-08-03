import SwiftUI

struct StockRowView: View {
    let symbol: StockSymbol
    let quote: StockQuote?
    let isLoading: Bool
    let lineOpacity: Double
    let lineWidth: Double
    let labelOpacity: Double
    let fontScale: Double
    let showStockMeta: Bool
    let compact: Bool

    private var changeRole: MarketColorRole {
        symbol.market.colorRole(isRising: (quote?.changePercent ?? 0) >= 0)
    }

    private var fontMultiplier: CGFloat {
        CGFloat(fontScale)
    }

    var body: some View {
        HStack(spacing: compact ? 7 : 10) {
            label
                .frame(width: compact ? 88 : 108, alignment: .leading)

            Group {
                if let quote, quote.points.count > 1 {
                    IntradayChartView(
                        points: quote.points,
                        dayOpen: quote.dayOpen,
                        colorRole: changeRole,
                        opacity: lineOpacity,
                        lineWidth: lineWidth
                    )
                } else {
                    placeholder
                }
            }
            .frame(maxWidth: .infinity)

            price
                .frame(width: compact ? 82 : 96, alignment: .trailing)
        }
        .padding(.horizontal, 3)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.045))
                .frame(height: 0.5)
        }
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: compact ? 1 : 3) {
            HStack(spacing: 4) {
                Text(symbol.name)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .font(.system(
                        size: (showStockMeta ? (compact ? 11 : 12) : (compact ? 14 : 16)) * fontMultiplier,
                        weight: .bold,
                        design: .rounded
                    ))
                    .foregroundStyle(
                        quote == nil
                            ? Color.white.opacity(labelOpacity)
                            : changeRole.color.opacity(labelOpacity)
                    )

                if quote?.isStale == true {
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.system(size: 8 * fontMultiplier))
                        .foregroundStyle(changeRole.color.opacity(labelOpacity))
                }
            }

            if showStockMeta {
                HStack(spacing: 4) {
                    Text(symbol.code)
                    Text(symbol.market.displayName)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(changeRole.color.opacity(0.14), in: Capsule())
                }
                .font(.system(size: (compact ? 7 : 8) * fontMultiplier, weight: .semibold, design: .monospaced))
                .foregroundStyle(
                    quote == nil
                        ? Color.white.opacity(labelOpacity)
                        : changeRole.color.opacity(labelOpacity)
                )
            }
        }
        .frame(maxHeight: .infinity, alignment: .center)
        .help(quote?.statusMessage ?? "\(symbol.market.displayName) · \(symbol.code)")
    }

    @ViewBuilder
    private var price: some View {
        if let quote {
            VStack(alignment: .trailing, spacing: compact ? 1 : 3) {
                Text(priceText(quote.lastPrice))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .font(.system(size: (compact ? 11 : 13) * fontMultiplier, weight: .bold, design: .monospaced))
                    .foregroundStyle(changeRole.color.opacity(labelOpacity))

                Text(percentText(quote.changePercent))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .font(.system(size: (compact ? 9 : 10) * fontMultiplier, weight: .black, design: .rounded))
                    .foregroundStyle(changeRole.color.opacity(labelOpacity))
            }
        } else {
            VStack(alignment: .trailing, spacing: 3) {
                ProgressView()
                    .controlSize(.mini)
                    .opacity(isLoading ? 0.6 : 0)
                Text(tr(isLoading ? "拉取中" : "暂无数据"))
                    .font(.system(size: 8 * fontMultiplier, weight: .medium))
                    .foregroundStyle(.white.opacity(labelOpacity))
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            Capsule()
                .fill(Color.white.opacity(0.04))
                .frame(height: 2)
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .opacity(0.55)
            }
        }
    }

    private func priceText(_ value: Double) -> String {
        if value >= 1_000 {
            return String(format: "%.2f", value)
        }
        if value >= 10 {
            return String(format: "%.2f", value)
        }
        return String(format: "%.3f", value)
    }

    private func percentText(_ value: Double) -> String {
        String(format: "%@%.2f%%", value >= 0 ? "+" : "", value)
    }
}

struct IntradayChartView: View {
    let points: [IntradayPoint]
    let dayOpen: Double
    let colorRole: MarketColorRole
    let opacity: Double
    let lineWidth: Double

    var body: some View {
        Canvas { context, size in
            guard points.count > 1 else { return }
            let chartLineWidth = CGFloat(lineWidth)

            let closes = points.map(\.close)
            let minimum = min(closes.min() ?? dayOpen, dayOpen)
            let maximum = max(closes.max() ?? dayOpen, dayOpen)
            let padding = max((maximum - minimum) * 0.14, max(abs(dayOpen) * 0.0008, 0.01))
            let low = minimum - padding
            let high = maximum + padding
            let range = max(high - low, 0.0001)

            func coordinate(index: Int, price: Double) -> CGPoint {
                let x = size.width * CGFloat(index) / CGFloat(max(points.count - 1, 1))
                let normalized = (price - low) / range
                let y = size.height * (1 - CGFloat(normalized))
                return CGPoint(x: x, y: y)
            }

            let openY = coordinate(index: 0, price: dayOpen).y
            var baseline = Path()
            baseline.move(to: CGPoint(x: 0, y: openY))
            baseline.addLine(to: CGPoint(x: size.width, y: openY))
            context.stroke(
                baseline,
                with: .color(.white.opacity(0.15 * opacity)),
                style: StrokeStyle(lineWidth: max(0.45, chartLineWidth * 0.42), dash: [3, 4])
            )

            var line = Path()
            line.move(to: coordinate(index: 0, price: points[0].close))
            for index in 1..<points.count {
                line.addLine(to: coordinate(index: index, price: points[index].close))
            }
            context.stroke(
                line,
                with: .color(colorRole.color.opacity(opacity)),
                style: StrokeStyle(lineWidth: chartLineWidth, lineCap: .round, lineJoin: .round)
            )

            if let last = points.last {
                let point = coordinate(index: points.count - 1, price: last.close)
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: point.x - max(1.8, chartLineWidth * 1.35),
                        y: point.y - max(1.8, chartLineWidth * 1.35),
                        width: max(3.6, chartLineWidth * 2.7),
                        height: max(3.6, chartLineWidth * 2.7)
                    )),
                    with: .color(colorRole.color.opacity(opacity))
                )
            }
        }
        .drawingGroup(opaque: false)
        .accessibilityLabel(tr("当日股价分时曲线"))
    }
}

extension MarketColorRole {
    var color: Color {
        switch self {
        case .red:
            Color(red: 1.0, green: 0.30, blue: 0.38)
        case .green:
            Color(red: 0.18, green: 0.82, blue: 0.55)
        }
    }
}
