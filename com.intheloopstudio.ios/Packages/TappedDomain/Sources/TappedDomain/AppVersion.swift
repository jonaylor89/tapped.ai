import Foundation

/// Semantic app version (`1.2.3`, optionally `+build`). Compared numerically component by component,
/// so `1.10.0 > 1.9.9` and `1.2 == 1.2.0`. The build number is ignored for gating.
public struct AppVersion: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let components: [Int]
    public let build: String?

    public init?(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "+", maxSplits: 1).map(String.init)
        guard let version = parts.first, !version.isEmpty else { return nil }
        let numbers = version.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !numbers.isEmpty, numbers.allSatisfy({ $0 != nil }) else { return nil }
        components = numbers.compactMap { $0 }
        build = parts.count > 1 ? parts[1] : nil
    }

    public init(_ components: [Int], build: String? = nil) {
        self.components = components
        self.build = build
    }

    /// `CFBundleShortVersionString` + `CFBundleVersion`.
    public static func current(bundle: Bundle = .main) -> AppVersion {
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return AppVersion(short).map { AppVersion($0.components, build: build) } ?? AppVersion([0], build: build)
    }

    public var description: String { components.map(String.init).joined(separator: ".") }

    /// Flutter `publishLatestAppVersion` format: `version+buildNumber`.
    public var firestoreValue: String { build.map { "\(description)+\($0)" } ?? description }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool { !(lhs < rhs) && !(rhs < lhs) }

    public func hash(into hasher: inout Hasher) {
        var trimmed = components
        while trimmed.last == 0 { trimmed.removeLast() }
        hasher.combine(trimmed)
    }
}
