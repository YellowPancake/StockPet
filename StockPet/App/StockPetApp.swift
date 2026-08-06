import AppKit
import Combine
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
        withExtendedLifetime(delegate) {}
    }

    private let store = StockStore()
    private let hotKeyController = GlobalHotKeyController()
    private var shortcutObserver: NSObjectProtocol?
    private var visibilityScheduleObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var settingsObserver: NSObjectProtocol?
    private var statusItem: NSStatusItem?
    private var petWindowController: NSWindowController?
    private var settingsWindowController: NSWindowController?
    private var petSizeObserver: AnyCancellable?
    private var visibilityScheduleTimer: Timer?

    private enum MenuTag: Int {
        case togglePet = 1
        case refresh = 2
        case clickThrough = 3
        case alwaysOnTop = 4
        case settings = 5
        case quit = 6
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        StartupDiagnostics.shared.begin()
        StartupDiagnostics.shared.mark("application-will-finish-launching")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        StartupDiagnostics.shared.mark("application-did-finish-launching")
        if let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }

        // LSUIElement already makes StockPet a menu-bar accessory. Avoid another
        // activation-policy transition during launch, and use the mature AppKit
        // status-item path to keep launch behavior deterministic across supported macOS releases.
        configureStatusItem()
        configurePetWindow()

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
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .stockPetOpenSettings,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.showSettings()
            }
        }
        visibilityScheduleObserver = NotificationCenter.default.addObserver(
            forName: .stockPetVisibilityScheduleChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.configureVisibilitySchedule(reconcileNow: true)
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.configureVisibilitySchedule(reconcileNow: true)
            }
        }
        updateGlobalShortcut()
        configureVisibilitySchedule(reconcileNow: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            StartupDiagnostics.shared.mark("store-starting")
            self?.store.start()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            StartupDiagnostics.shared.markStable()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyController.unregister()
        if let shortcutObserver {
            NotificationCenter.default.removeObserver(shortcutObserver)
        }
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
        if let visibilityScheduleObserver {
            NotificationCenter.default.removeObserver(visibilityScheduleObserver)
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        visibilityScheduleTimer?.invalidate()
        petSizeObserver?.cancel()
        store.stop()
        StartupDiagnostics.shared.finish()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func updateGlobalShortcut() {
        hotKeyController.register(
            enabled: store.shortcutEnabled,
            modifier: store.shortcutModifier,
            key: store.shortcutKey
        )
    }

    private func togglePetWindow() {
        guard let window = petWindow else {
            recoverPetWindowIfNeeded()
            return
        }

        setPetWindowVisible(!window.isVisible)
    }

    private func setPetWindowVisible(_ visible: Bool) {
        guard let window = petWindow else { return }
        if visible {
            WindowConfigurator.recoverFrameIfNeeded(for: window)
            window.orderFrontRegardless()
        } else {
            window.orderOut(nil)
        }
        updateMenuItems()
    }

    private func configureVisibilitySchedule(reconcileNow: Bool) {
        visibilityScheduleTimer?.invalidate()
        visibilityScheduleTimer = nil
        guard store.visibilityScheduleEnabled,
              store.scheduledShowMinutes != store.scheduledHideMinutes
        else { return }

        let now = Date()
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let nowMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if reconcileNow,
           let shouldShow = DailyVisibilitySchedule.shouldShow(
               nowMinutes: nowMinutes,
               showMinutes: store.scheduledShowMinutes,
               hideMinutes: store.scheduledHideMinutes
           ) {
            setPetWindowVisible(shouldShow)
        }

        let nextDates = [store.scheduledShowMinutes, store.scheduledHideMinutes].compactMap { minutes in
            calendar.nextDate(
                after: now,
                matching: DateComponents(hour: minutes / 60, minute: minutes % 60, second: 0),
                matchingPolicy: .nextTime
            )
        }
        guard let nextDate = nextDates.min() else { return }
        let timer = Timer(fire: nextDate, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.configureVisibilitySchedule(reconcileNow: true)
            }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        visibilityScheduleTimer = timer
    }

    private var petWindow: NSWindow? {
        petWindowController?.window
    }

    private func configurePetWindow() {
        let rootView = FloatingPetView()
            .environmentObject(store)
            .environment(\.locale, stockPetLocale)
            .background(
                WindowConfigurator(
                    clickThrough: store.clickThrough,
                    alwaysOnTop: store.alwaysOnTop
                )
            )
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.view.layoutSubtreeIfNeeded()

        let window = NSWindow(contentViewController: hostingController)
        window.styleMask = .borderless
        window.isReleasedWhenClosed = false

        var initialSize = hostingController.view.fittingSize
        if initialSize.width < 100 || initialSize.height < 50 {
            initialSize = NSSize(width: 560, height: 252)
        }
        window.setContentSize(initialSize)
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let visible = screen.visibleFrame
            window.setFrameOrigin(NSPoint(
                x: max(visible.minX, visible.maxX - initialSize.width - 24),
                y: max(visible.minY, visible.maxY - initialSize.height - 24)
            ))
        }

        petWindowController = NSWindowController(window: window)
        petSizeObserver = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.resizePetWindowToFit()
            }
        }
        window.orderFrontRegardless()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.resizePetWindowToFit()
            if self.store.visibilityScheduleEnabled {
                WindowConfigurator.recoverFrameIfNeeded(for: window)
                self.configureVisibilitySchedule(reconcileNow: true)
            } else {
                self.recoverPetWindowIfNeeded()
            }
            StartupDiagnostics.shared.mark("pet-window-ready")
        }
        StartupDiagnostics.shared.mark("pet-window-created")
    }

    private func resizePetWindowToFit() {
        guard let window = petWindow,
              let contentView = window.contentView
        else { return }
        contentView.layoutSubtreeIfNeeded()
        let fittingSize = contentView.fittingSize
        guard fittingSize.width >= 100, fittingSize.height >= 50 else { return }
        let current = window.frame
        guard abs(current.width - fittingSize.width) > 0.5 ||
                abs(current.height - fittingSize.height) > 0.5
        else { return }
        let resized = NSRect(
            x: current.minX,
            y: current.maxY - fittingSize.height,
            width: fittingSize.width,
            height: fittingSize.height
        )
        window.setFrame(resized, display: true)
        WindowConfigurator.recoverFrameIfNeeded(for: window)
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "chart.xyaxis.line",
                accessibilityDescription: tr("Stock Pet")
            )
            button.toolTip = tr("Stock Pet")
        }
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(menuItem("显示桌宠", action: #selector(togglePetMenuItem), tag: .togglePet))
        menu.addItem(menuItem("立即刷新", action: #selector(refreshMenuItem), tag: .refresh, key: "r"))
        menu.addItem(menuItem("锁定并穿透鼠标", action: #selector(clickThroughMenuItem), tag: .clickThrough))
        menu.addItem(menuItem("始终置顶", action: #selector(alwaysOnTopMenuItem), tag: .alwaysOnTop))
        menu.addItem(.separator())
        menu.addItem(menuItem("设置…", action: #selector(settingsMenuItem), tag: .settings, key: ","))
        menu.addItem(.separator())
        menu.addItem(menuItem("退出 Stock Pet", action: #selector(quitMenuItem), tag: .quit, key: "q"))
        item.menu = menu
        statusItem = item
        updateMenuItems()
        StartupDiagnostics.shared.mark("status-item-ready")
    }

    private func menuItem(
        _ title: String,
        action: Selector,
        tag: MenuTag,
        key: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: tr(title), action: action, keyEquivalent: key)
        item.target = self
        item.tag = tag.rawValue
        return item
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateMenuItems()
    }

    private func updateMenuItems() {
        guard let menu = statusItem?.menu else { return }
        menu.item(withTag: MenuTag.togglePet.rawValue)?.title = tr(
            petWindow?.isVisible == true ? "隐藏桌宠" : "显示桌宠"
        )
        menu.item(withTag: MenuTag.clickThrough.rawValue)?.state =
            store.clickThrough ? .on : .off
        menu.item(withTag: MenuTag.alwaysOnTop.rawValue)?.state =
            store.alwaysOnTop ? .on : .off
    }

    @objc private func togglePetMenuItem() {
        togglePetWindow()
    }

    @objc private func refreshMenuItem() {
        Task { await store.refreshAll() }
    }

    @objc private func clickThroughMenuItem() {
        store.clickThrough.toggle()
        updateMenuItems()
    }

    @objc private func alwaysOnTopMenuItem() {
        store.alwaysOnTop.toggle()
        updateMenuItems()
    }

    @objc private func settingsMenuItem() {
        showSettings()
    }

    @objc private func quitMenuItem() {
        NSApp.terminate(nil)
    }

    private func showSettings() {
        if settingsWindowController == nil {
            let rootView = SettingsView()
                .environmentObject(store)
                .environment(\.locale, stockPetLocale)
                .frame(width: 640, height: 720)
            let controller = NSHostingController(rootView: rootView)
            let window = NSWindow(contentViewController: controller)
            window.title = tr("Stock Pet 设置")
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 640, height: 720))
            window.minSize = NSSize(width: 600, height: 620)
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindowController = NSWindowController(window: window)
        }
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @discardableResult
    private func recoverPetWindowIfNeeded() -> Bool {
        guard let window = petWindow else {
            StartupDiagnostics.shared.mark("pet-window-not-ready")
            return false
        }
        WindowConfigurator.recoverFrameIfNeeded(for: window)
        if !window.isVisible {
            window.orderFrontRegardless()
        }
        updateMenuItems()
        StartupDiagnostics.shared.mark("pet-window-ready")
        return true
    }
}
