import AppKit
import SwiftUI

@main
struct StockPetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = StockStore()

    var body: some Scene {
        WindowGroup("Stock Pet", id: "stock-pet") {
            FloatingPetView()
                .environmentObject(store)
                .environment(\.locale, stockPetLocale)
                .background(
                    WindowConfigurator(
                        clickThrough: store.clickThrough,
                        alwaysOnTop: store.alwaysOnTop
                    )
                )
                .task {
                    appDelegate.store = store
                    if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
                        store.start()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)

        MenuBarExtra("Stock Pet", systemImage: "chart.xyaxis.line") {
            MenuBarContent()
                .environmentObject(store)
                .environment(\.locale, stockPetLocale)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(store)
                .environment(\.locale, stockPetLocale)
                .frame(width: 640, height: 720)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: StockStore? {
        didSet { updateGlobalShortcut() }
    }

    private let hotKeyController = GlobalHotKeyController()
    private var shortcutObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }
        NSApp.setActivationPolicy(.accessory)

        hotKeyController.onPress = { [weak self] in
            self?.togglePetWindow()
        }
        shortcutObserver = NotificationCenter.default.addObserver(
            forName: .stockPetShortcutChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateGlobalShortcut()
            }
        }
        updateGlobalShortcut()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyController.unregister()
        if let shortcutObserver {
            NotificationCenter.default.removeObserver(shortcutObserver)
        }
        store?.stop()
    }

    private func updateGlobalShortcut() {
        guard let store else { return }
        hotKeyController.register(
            enabled: store.shortcutEnabled,
            modifier: store.shortcutModifier,
            key: store.shortcutKey
        )
    }

    private func togglePetWindow() {
        guard let window = NSApp.windows.first(where: {
            $0.identifier?.rawValue == WindowConfigurator.windowIdentifier
        }) else { return }

        if window.isVisible {
            window.orderOut(nil)
        } else {
            window.orderFrontRegardless()
        }
    }
}

struct MenuBarContent: View {
    @EnvironmentObject private var store: StockStore

    var body: some View {
        Button(tr(petWindow?.isVisible == true ? "隐藏桌宠" : "显示桌宠")) {
            togglePetWindow()
        }

        Button(tr("立即刷新")) {
            Task { await store.refreshAll() }
        }
        .keyboardShortcut("r")

        Toggle(tr("锁定并穿透鼠标"), isOn: $store.clickThrough)
        Toggle(tr("始终置顶"), isOn: $store.alwaysOnTop)

        Divider()

        if #available(macOS 14.0, *) {
            SettingsLink {
                Text(tr("设置…"))
            }
        } else {
            Button(tr("设置…")) {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        Divider()

        Button(tr("退出 Stock Pet")) {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var petWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == WindowConfigurator.windowIdentifier }
    }

    private func togglePetWindow() {
        guard let window = petWindow else { return }
        if window.isVisible {
            window.orderOut(nil)
        } else {
            window.orderFrontRegardless()
        }
    }
}
