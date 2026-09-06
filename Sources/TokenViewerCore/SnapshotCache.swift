import Foundation

public struct SnapshotCache: Sendable {
    public var directory: URL
    public init(directory: URL) { self.directory = directory }
    public func load(_ provider: ProviderID) -> UsageSnapshot? {
        let path = directory.appendingPathComponent("\(provider.rawValue).json")
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path.path),
              let size = attributes[.size] as? Int, size < 262_144,
              let data = try? Data(contentsOf: path),
              let snapshot = try? JSONDecoder().decode(UsageSnapshot.self, from: data), snapshot.provider == provider,
              !snapshot.windows.isEmpty,
              snapshot.windows.allSatisfy({ $0.usedPercent.isFinite && $0.usedPercent >= 0 }) else { return nil }
        return snapshot
    }
    public func save(_ snapshot: UsageSnapshot) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent("\(snapshot.provider.rawValue).json")
        try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
