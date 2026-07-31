import SwiftUI

struct FloatingPetView: View {
    @EnvironmentObject private var store: StockStore
    @Environment(\.openSettings) private var openSettings
    private let maximumVisibleRows = 8

    private var rowHeight: CGFloat {
        store.compactMode ? 45 : 58
    }

    private var baseWidth: CGFloat {
        store.compactMode ? 460 : 560
    }

    private var baseHeight: CGFloat {
        let rows = max(min(store.symbols.count, maximumVisibleRows), 1)
        return CGFloat(rows) * rowHeight + 20
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                if store.symbols.isEmpty {
                    emptyState
                        .frame(height: rowHeight)
                } else {
                    ScrollView(.vertical, showsIndicators: store.symbols.count > maximumVisibleRows) {
                        LazyVStack(spacing: 0) {
                            ForEach(store.symbols) { symbol in
                                StockRowView(
                                    symbol: symbol,
                                    quote: store.quotes[symbol.id],
                                    isLoading: store.loadingIDs.contains(symbol.id),
                                    lineOpacity: store.lineOpacity,
                                    labelOpacity: store.labelOpacity,
                                    compact: store.compactMode
                                )
                                .frame(height: rowHeight)
                            }
                        }
                    }
                }
            }
            .padding(10)
            .background(panelBackground)

            if let alert = store.activeAlert {
                MascotAlertView(alert: alert)
                    .opacity(store.alertOpacity)
                    .padding(.bottom, 12)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .scale(scale: 0.65)).combined(with: .opacity),
                        removal: .scale(scale: 0.8).combined(with: .opacity)
                    ))
                    .zIndex(10)
            }
        }
        .frame(width: baseWidth, height: baseHeight)
        .contentShape(Rectangle())
        .onReceive(NotificationCenter.default.publisher(for: .stockPetOpenSettings)) { _ in
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: store.activeAlert?.id)
        .animation(.easeInOut(duration: 0.2), value: store.compactMode)
        .scaleEffect(store.displayScale, anchor: .topLeading)
        .frame(
            width: baseWidth * store.displayScale,
            height: baseHeight * store.displayScale,
            alignment: .topLeading
        )
        .animation(.easeInOut(duration: 0.18), value: store.displayScale)
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.black.opacity(store.backgroundOpacity))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(store.backgroundOpacity > 0.05 ? 0.14 : 0), lineWidth: 0.7)
            }
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
            Text("双击添加股票")
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(.white.opacity(0.6))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
