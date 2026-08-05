import AppKit
import SwiftUI

struct WindowConfigurator: NSViewRepresentable {
    static let windowIdentifier = "stock-pet-floating-window"

    let clickThrough: Bool
    let alwaysOnTop: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(view.window, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(nsView.window, coordinator: context.coordinator)
        }
    }

    private func configure(_ window: NSWindow?, coordinator: Coordinator) {
        guard let window else { return }
        window.identifier = NSUserInterfaceItemIdentifier(Self.windowIdentifier)
        window.styleMask = .borderless
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.isMovableByWindowBackground = true
        window.level = alwaysOnTop ? .floating : .normal
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.ignoresMouseEvents = clickThrough
        window.setFrameAutosaveName("StockPetFloatingFrame")
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
        Self.recoverFrameIfNeeded(for: window)
        coordinator.install(on: window)
    }

    static func recoverFrameIfNeeded(for window: NSWindow) {
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        let hasUsefulIntersection = visibleFrames.contains {
            window.frame.intersection($0).width >= 80 && window.frame.intersection($0).height >= 50
        }
        guard !hasUsefulIntersection, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: max(visible.minX, visible.maxX - window.frame.width - 24),
            y: max(visible.minY, visible.maxY - window.frame.height - 24)
        )
        window.setFrameOrigin(origin)
    }

    final class Coordinator {
        private weak var window: NSWindow?
        private var monitor: Any?

        func install(on window: NSWindow) {
            guard self.window !== window || monitor == nil else { return }
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            self.window = window
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                if event.window === self?.window, event.clickCount == 2 {
                    NotificationCenter.default.post(name: .stockPetOpenSettings, object: nil)
                }
                return event
            }
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}

extension Notification.Name {
    static let stockPetOpenSettings = Notification.Name("stockPet.openSettings")
}
