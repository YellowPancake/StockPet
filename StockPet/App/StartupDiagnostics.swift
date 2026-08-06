import Foundation

final class StartupDiagnostics {
    static let shared = StartupDiagnostics()

    private let fileManager = FileManager.default
    private var logURL: URL?
    private var markerURL: URL?
    private let lock = NSLock()

    private init() {}

    func begin() {
        lock.lock()
        defer { lock.unlock() }

        guard let support = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return }
        let directoryName = Bundle.main.bundleIdentifier ?? "StockPet"
        let directory = support.appendingPathComponent(directoryName, isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let log = directory.appendingPathComponent("startup.log")
        let marker = directory.appendingPathComponent("launch-in-progress")
        logURL = log
        markerURL = marker

        if fileManager.fileExists(atPath: marker.path) {
            exportPreviousFailedLaunch(from: log)
        }

        let header = """

        === StockPet launch ===
        time: \(ISO8601DateFormatter().string(from: Date()))
        version: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown")
        build: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown")
        system: \(ProcessInfo.processInfo.operatingSystemVersionString)
        architecture: \(Self.architecture)
        """
        append(header, to: log)
        try? Data("launching".utf8).write(to: marker, options: .atomic)
    }

    func mark(_ stage: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let logURL else { return }
        append("\(ISO8601DateFormatter().string(from: Date())) \(stage)", to: logURL)
    }

    func markStable() {
        mark("launch-stable")
        lock.lock()
        defer { lock.unlock() }
        if let markerURL {
            try? fileManager.removeItem(at: markerURL)
        }
    }

    func finish() {
        mark("application-will-terminate")
        lock.lock()
        defer { lock.unlock() }
        if let markerURL {
            try? fileManager.removeItem(at: markerURL)
        }
    }

    private func exportPreviousFailedLaunch(from log: URL) {
        guard fileManager.fileExists(atPath: log.path),
              let desktop = fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first
        else { return }
#if ENGLISH_BUILD
        let prefix = "StockPet-Startup-Diagnostic"
#else
        let prefix = "盘宠-启动诊断"
#endif
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "\(prefix)-\(formatter.string(from: Date())).txt"
        let destination = desktop.appendingPathComponent(name)
        try? fileManager.copyItem(at: log, to: destination)
    }

    private func append(_ text: String, to url: URL) {
        let data = Data((text + "\n").utf8)
        if !fileManager.fileExists(atPath: url.path) {
            try? data.write(to: url, options: .atomic)
            return
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            return
        }
    }

    private static var architecture: String {
#if arch(arm64)
        "arm64"
#elseif arch(x86_64)
        "x86_64"
#else
        "unknown"
#endif
    }
}
