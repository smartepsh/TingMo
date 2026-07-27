import AppKit
import CryptoKit
import Foundation
import Observation

/// A normalized dotted numeric app version. GitHub tags may start with `v`
/// and may include build metadata; both are ignored for release comparison.
struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    private let components: [Int]

    init?(_ value: String) {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.first == "v" || normalized.first == "V" {
            normalized.removeFirst()
        }
        if let buildMetadataIndex = normalized.firstIndex(of: "+") {
            normalized = String(normalized[..<buildMetadataIndex])
        }

        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              parts.allSatisfy({ Int($0) != nil }) else {
            return nil
        }

        components = parts.compactMap { Int($0) }
    }

    var description: String {
        components.map(String.init).joined(separator: ".")
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        compare(lhs, rhs) == 0
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        compare(lhs, rhs) < 0
    }

    private static func compare(_ lhs: Self, _ rhs: Self) -> Int {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right ? -1 : 1 }
        }
        return 0
    }
}

struct GitHubRelease: Decodable, Equatable, Sendable {
    struct Asset: Decodable, Equatable, Sendable {
        let name: String
        let browserDownloadURL: URL
        let digest: String?

        var sha256Digest: String? {
            guard let digest, digest.lowercased().hasPrefix("sha256:") else { return nil }
            return String(digest.dropFirst("sha256:".count)).lowercased()
        }

        private enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case digest
        }
    }

    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: URL
    let assets: [Asset]

    var version: AppVersion? { AppVersion(tagName) }

    var diskImageAsset: Asset? {
        assets.first { $0.name.lowercased().hasSuffix(".dmg") }
    }

    static func decode(_ data: Data) throws -> Self {
        try JSONDecoder().decode(Self.self, from: data)
    }

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case assets
    }
}

enum GitHubReleaseClient {
    static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/smartepsh/TingMo/releases/latest"
    )!

    enum ClientError: LocalizedError {
        case invalidResponse
        case server(status: Int)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                String(localized: "GitHub returned an invalid release response.")
            case .server(let status):
                String(localized: "GitHub returned an error (HTTP \(status)).")
            }
        }
    }

    static func fetchLatest(session: URLSession = .shared) async throws -> GitHubRelease {
        var request = URLRequest(url: latestReleaseURL, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("TingMo-Updater", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw ClientError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw ClientError.server(status: response.statusCode)
        }

        do {
            return try GitHubRelease.decode(data)
        } catch {
            throw ClientError.invalidResponse
        }
    }
}

@Observable
@MainActor
final class UpdateManager {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case updateAvailable
        case downloading
        case downloaded(URL)
        case failed(String)
    }

    private static let automaticChecksKey = "Updater.automaticChecksEnabled"
    private static let lastAutomaticCheckKey = "Updater.lastAutomaticCheck"
    private static let automaticCheckInterval: TimeInterval = 24 * 60 * 60

    private let session: URLSession
    private let defaults: UserDefaults

    let currentVersionString: String
    private(set) var state: State = .idle
    private(set) var latestRelease: GitHubRelease?

    var automaticChecksEnabled: Bool {
        didSet { defaults.set(automaticChecksEnabled, forKey: Self.automaticChecksKey) }
    }

    var isBusy: Bool {
        state == .checking || state == .downloading
    }

    init(
        currentVersionString: String? = nil,
        session: URLSession = .shared,
        defaults: UserDefaults = .standard
    ) {
        self.currentVersionString = currentVersionString
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.0.0"
        self.session = session
        self.defaults = defaults

        if defaults.object(forKey: Self.automaticChecksKey) == nil {
            automaticChecksEnabled = true
        } else {
            automaticChecksEnabled = defaults.bool(forKey: Self.automaticChecksKey)
        }
    }

    func checkAutomaticallyIfNeeded(now: Date = Date()) async {
        guard automaticChecksEnabled else { return }
        if let lastCheck = defaults.object(forKey: Self.lastAutomaticCheckKey) as? Date,
           now.timeIntervalSince(lastCheck) < Self.automaticCheckInterval {
            return
        }

        // Record the attempt before starting so a temporary outage does not
        // hammer GitHub every time the menu is opened.
        defaults.set(now, forKey: Self.lastAutomaticCheckKey)
        await checkForUpdates()
    }

    func checkForUpdates() async {
        guard !isBusy else { return }
        state = .checking

        do {
            let release = try await GitHubReleaseClient.fetchLatest(session: session)
            NSLog(
                "[TingMo][Updater] GitHub latest release: tag=\(release.tagName), "
                    + "version=\(release.version?.description ?? "<invalid>"), "
                    + "current=\(currentVersionString)"
            )
            guard let currentVersion = AppVersion(currentVersionString),
                  let latestVersion = release.version else {
                throw GitHubReleaseClient.ClientError.invalidResponse
            }

            latestRelease = release
            state = latestVersion > currentVersion ? .updateAvailable : .upToDate
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func downloadAvailableUpdate() async {
        guard !isBusy,
              let release = latestRelease,
              let asset = release.diskImageAsset else {
            if let releaseURL = latestRelease?.htmlURL {
                NSWorkspace.shared.open(releaseURL)
            }
            return
        }

        state = .downloading
        do {
            let (temporaryURL, response) = try await session.download(from: asset.browserDownloadURL)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else {
                throw GitHubReleaseClient.ClientError.invalidResponse
            }

            try Self.verifyDownload(at: temporaryURL, expectedSHA256: asset.sha256Digest)
            let destinationURL = try Self.moveToDownloads(temporaryURL, named: asset.name)
            state = .downloaded(destinationURL)
            NSWorkspace.shared.open(destinationURL)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func openDownloadedUpdate() {
        guard case .downloaded(let url) = state else { return }
        NSWorkspace.shared.open(url)
    }

    func openLatestReleasePage() {
        guard let url = latestRelease?.htmlURL else { return }
        NSWorkspace.shared.open(url)
    }

    private static func verifyDownload(at url: URL, expectedSHA256: String?) throws {
        guard let expectedSHA256 else { return }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == expectedSHA256 else {
            throw UpdateError.checksumMismatch
        }
    }

    private static func moveToDownloads(_ temporaryURL: URL, named assetName: String) throws -> URL {
        let safeName = URL(fileURLWithPath: assetName).lastPathComponent
        guard safeName == assetName, safeName.lowercased().hasSuffix(".dmg") else {
            throw UpdateError.invalidAssetName
        }

        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let destination = downloads.appendingPathComponent(safeName, isDirectory: false)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    private enum UpdateError: LocalizedError {
        case checksumMismatch
        case invalidAssetName

        var errorDescription: String? {
            switch self {
            case .checksumMismatch:
                String(localized: "The downloaded update failed its integrity check.")
            case .invalidAssetName:
                String(localized: "The release does not contain a valid macOS installer.")
            }
        }
    }
}
