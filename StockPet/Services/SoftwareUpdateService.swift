import CryptoKit
import Foundation

struct AvailableSoftwareUpdate: Sendable {
    let version: String
    let notes: String
    let releasePageURL: URL
    let assetName: String
    let assetURL: URL
    let digest: String
}

enum SoftwareUpdateCheckResult: Sendable {
    case upToDate(version: String)
    case available(AvailableSoftwareUpdate)
}

actor SoftwareUpdateService {
    private let session: URLSession
    private let releasesURL = URL(
        string: "https://api.github.com/repos/YellowPancake/StockPet/releases/latest"
    )!

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 180
            configuration.waitsForConnectivity = false
            self.session = URLSession(configuration: configuration)
        }
    }

    func check(
        currentVersion: String,
        assetName: String
    ) async throws -> SoftwareUpdateCheckResult {
        var request = URLRequest(
            url: releasesURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 20
        )
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("StockPet/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else {
            throw SoftwareUpdateError.checkFailed
        }
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        let latestVersion = Self.normalizedVersion(release.tagName)
        guard Self.isVersion(latestVersion, newerThan: currentVersion) else {
            return .upToDate(version: currentVersion)
        }
        guard let asset = release.assets.first(where: { $0.name == assetName }),
              let releasePageURL = URL(string: release.htmlURL),
              let assetURL = URL(string: asset.browserDownloadURL),
              let digest = asset.digest,
              digest.hasPrefix("sha256:")
        else {
            throw SoftwareUpdateError.missingAsset
        }
        return .available(
            AvailableSoftwareUpdate(
                version: latestVersion,
                notes: release.body ?? "",
                releasePageURL: releasePageURL,
                assetName: asset.name,
                assetURL: assetURL,
                digest: digest
            )
        )
    }

    func download(_ update: AvailableSoftwareUpdate) async throws -> URL {
        var request = URLRequest(
            url: update.assetURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 180
        )
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("StockPet/\(update.version)", forHTTPHeaderField: "User-Agent")
        let (temporaryURL, response) = try await session.download(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else {
            throw SoftwareUpdateError.downloadFailed
        }

        let data = try Data(contentsOf: temporaryURL, options: .mappedIfSafe)
        let actualDigest = "sha256:" + SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        guard actualDigest == update.digest.lowercased() else {
            throw SoftwareUpdateError.digestMismatch
        }

        let downloads = FileManager.default.urls(
            for: .downloadsDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
        let destination = Self.availableDestination(
            in: downloads,
            assetName: update.assetName,
            version: update.version
        )
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let left = normalizedVersion(candidate).split(separator: ".").map { Int($0) ?? 0 }
        let right = normalizedVersion(current).split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(left.count, right.count) {
            let lhs = index < left.count ? left[index] : 0
            let rhs = index < right.count ? right[index] : 0
            if lhs != rhs { return lhs > rhs }
        }
        return false
    }

    private static func normalizedVersion(_ raw: String) -> String {
        raw.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            .split(separator: "-")
            .first
            .map(String.init) ?? "0"
    }

    private static func availableDestination(
        in directory: URL,
        assetName: String,
        version: String
    ) -> URL {
        let source = URL(fileURLWithPath: assetName)
        let base = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        var candidate = directory.appendingPathComponent("\(base)-v\(version).\(ext)")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent(
                "\(base)-v\(version)-\(suffix).\(ext)"
            )
            suffix += 1
        }
        return candidate
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String
    let body: String?
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body
        case assets
    }
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: String
    let digest: String?

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case digest
    }
}

enum SoftwareUpdateError: LocalizedError {
    case checkFailed
    case missingAsset
    case downloadFailed
    case digestMismatch

    var errorDescription: String? {
        switch self {
        case .checkFailed: tr("检查更新失败，请稍后重试")
        case .missingAsset: tr("新版本缺少适用于当前系统的安装包")
        case .downloadFailed: tr("更新包下载失败，请稍后重试")
        case .digestMismatch: tr("更新包校验失败，已停止下载")
        }
    }
}
