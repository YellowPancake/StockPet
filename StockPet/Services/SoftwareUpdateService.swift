import CryptoKit
import Foundation

enum SoftwareUpdateRoute: String, CaseIterable, Hashable, Sendable {
    case routeOne
    case routeTwo
}

struct SoftwareUpdateDownload: Sendable {
    let route: SoftwareUpdateRoute
    let assetName: String
    let assetURL: URL
    let digest: String
}

struct AvailableSoftwareUpdate: Sendable {
    let version: String
    let notes: String
    let downloads: [SoftwareUpdateRoute: SoftwareUpdateDownload]
}

enum SoftwareUpdateCheckResult: Sendable {
    case upToDate(version: String)
    case available(AvailableSoftwareUpdate)
}

actor SoftwareUpdateService {
    private let session: URLSession
    private let githubReleaseURL = URL(
        string: "https://api.github.com/repos/YellowPancake/StockPet/releases/latest"
    )!
    private let giteeReleaseURL = URL(
        string: "https://gitee.com/api/v5/repos/YBigPie/StockPet/releases/latest"
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
        let outcomes = await withTaskGroup(of: ProviderOutcome.self) { group in
            group.addTask {
                do {
                    return .success(try await self.fetchGitHub(assetName: assetName))
                } catch {
                    return .failure
                }
            }
            group.addTask {
                do {
                    return .success(try await self.fetchGitee(assetName: assetName))
                } catch {
                    return .failure
                }
            }

            var values: [ProviderOutcome] = []
            for await outcome in group { values.append(outcome) }
            return values
        }

        let candidates = outcomes.compactMap { outcome -> RouteCandidate? in
            guard case .success(let candidate) = outcome else { return nil }
            return candidate
        }
        guard !candidates.isEmpty else { throw SoftwareUpdateError.checkFailed }

        let newerCandidates = candidates.filter {
            Self.isVersion($0.version, newerThan: currentVersion)
        }
        guard let latest = newerCandidates.max(by: {
            Self.isVersion($1.version, newerThan: $0.version)
        }) else {
            return .upToDate(version: currentVersion)
        }

        let downloads = Dictionary(
            uniqueKeysWithValues: newerCandidates
                .filter { Self.normalizedVersion($0.version) == Self.normalizedVersion(latest.version) }
                .map { ($0.download.route, $0.download) }
        )
        guard !downloads.isEmpty else { throw SoftwareUpdateError.missingAsset }
        let notes = newerCandidates
            .first(where: { !$0.notes.isEmpty && $0.version == latest.version })?
            .notes ?? latest.notes
        return .available(
            AvailableSoftwareUpdate(
                version: latest.version,
                notes: notes,
                downloads: downloads
            )
        )
    }

    func download(
        _ update: AvailableSoftwareUpdate,
        route: SoftwareUpdateRoute
    ) async throws -> URL {
        guard let download = update.downloads[route] else {
            throw SoftwareUpdateError.missingRoute
        }
        var request = URLRequest(
            url: download.assetURL,
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
        guard actualDigest == download.digest.lowercased() else {
            throw SoftwareUpdateError.digestMismatch
        }

        let downloads = FileManager.default.urls(
            for: .downloadsDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
        let destination = Self.availableDestination(
            in: downloads,
            assetName: download.assetName,
            version: update.version
        )
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    private func fetchGitHub(assetName: String) async throws -> RouteCandidate {
        var request = URLRequest(
            url: githubReleaseURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 20
        )
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("StockPet", forHTTPHeaderField: "User-Agent")
        let data = try await responseData(for: request)
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard let asset = release.assets.first(where: { $0.name == assetName }),
              let assetURL = URL(string: asset.browserDownloadURL),
              let digest = asset.digest,
              digest.hasPrefix("sha256:")
        else {
            throw SoftwareUpdateError.missingAsset
        }
        return RouteCandidate(
            version: Self.normalizedVersion(release.tagName),
            notes: release.body ?? "",
            download: SoftwareUpdateDownload(
                route: .routeOne,
                assetName: asset.name,
                assetURL: assetURL,
                digest: digest.lowercased()
            )
        )
    }

    private func fetchGitee(assetName: String) async throws -> RouteCandidate {
        var request = URLRequest(
            url: giteeReleaseURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 20
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("StockPet", forHTTPHeaderField: "User-Agent")
        let data = try await responseData(for: request)
        let release = try JSONDecoder().decode(GiteeRelease.self, from: data)

        let attachmentsURL = URL(
            string: "https://gitee.com/api/v5/repos/YBigPie/StockPet/releases/\(release.id)/attach_files?per_page=100"
        )!
        var attachmentsRequest = URLRequest(
            url: attachmentsURL,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 20
        )
        attachmentsRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        attachmentsRequest.setValue("StockPet", forHTTPHeaderField: "User-Agent")
        let attachmentsData = try await responseData(for: attachmentsRequest)
        let attachments = try JSONDecoder().decode([GiteeAttachment].self, from: attachmentsData)
        guard let asset = attachments.first(where: { $0.name == assetName }),
              let assetURL = URL(string: asset.browserDownloadURL),
              let digest = Self.digest(for: assetName, in: release.body ?? "")
        else {
            throw SoftwareUpdateError.missingAsset
        }
        return RouteCandidate(
            version: Self.normalizedVersion(release.tagName),
            notes: release.body ?? "",
            download: SoftwareUpdateDownload(
                route: .routeTwo,
                assetName: asset.name,
                assetURL: assetURL,
                digest: digest
            )
        )
    }

    private func responseData(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else {
            throw SoftwareUpdateError.checkFailed
        }
        return data
    }

    static func digest(for assetName: String, in notes: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: assetName)
        let pattern = "(?im)^SHA256\\s*\\(\(escapedName)\\)\\s*:\\s*([0-9a-f]{64})\\s*$"
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: notes,
                range: NSRange(notes.startIndex..., in: notes)
              ),
              let range = Range(match.range(at: 1), in: notes)
        else { return nil }
        return "sha256:" + notes[range].lowercased()
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

private struct RouteCandidate: Sendable {
    let version: String
    let notes: String
    let download: SoftwareUpdateDownload
}

private enum ProviderOutcome: Sendable {
    case success(RouteCandidate)
    case failure
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let body: String?
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
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

private struct GiteeRelease: Decodable {
    let id: Int
    let tagName: String
    let body: String?

    enum CodingKeys: String, CodingKey {
        case id
        case tagName = "tag_name"
        case body
    }
}

private struct GiteeAttachment: Decodable {
    let name: String
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

enum SoftwareUpdateError: LocalizedError {
    case checkFailed
    case missingAsset
    case missingRoute
    case downloadFailed
    case digestMismatch

    var errorDescription: String? {
        switch self {
        case .checkFailed: tr("检查更新失败，请稍后重试")
        case .missingAsset: tr("新版本缺少适用于当前系统的安装包")
        case .missingRoute: tr("所选下载路线暂时不可用，请尝试另一条路线")
        case .downloadFailed: tr("更新包下载失败，请稍后重试")
        case .digestMismatch: tr("更新包校验失败，已停止下载")
        }
    }
}
