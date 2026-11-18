import Foundation

public struct DiskStats: Equatable {
    public let volumePath: String
    public let totalBytes: Int64
    public let freeBytes: Int64
    public let importantAvailableBytes: Int64
    public let volumeName: String
    public let timestamp: Date

    private static let formatterLock = NSLock()
    private static let sharedFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .decimal // macOS Finder & Sistem Ayarları standardı (1 GB = 10^9 B)
        formatter.allowedUnits = [.useGB, .useTB, .useMB]
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    // Decimal GB eşikleri (ByteCountFormatter .decimal ile tutarlı)
    public static let lowSpaceThresholdBytes: Int64 = 10_000_000_000      // 10 GB
    public static let criticalSpaceThresholdBytes: Int64 = 5_000_000_000  // 5 GB

    public var usedBytes: Int64 {
        return max(0, totalBytes - freeBytes)
    }

    public var purgeableBytes: Int64 {
        return max(0, importantAvailableBytes - freeBytes)
    }

    public var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1.0, max(0.0, Double(usedBytes) / Double(totalBytes)))
    }

    public var freeFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1.0, max(0.0, Double(freeBytes) / Double(totalBytes)))
    }

    public var isLowSpace: Bool {
        guard totalBytes > 0 else { return false }
        return freeBytes < DiskStats.lowSpaceThresholdBytes || freeFraction < 0.10
    }

    public var isCriticalSpace: Bool {
        guard totalBytes > 0 else { return false }
        return freeBytes < DiskStats.criticalSpaceThresholdBytes || freeFraction < 0.05
    }

    public var totalFormatted: String {
        return DiskStats.format(totalBytes)
    }

    public var freeFormatted: String {
        return DiskStats.format(freeBytes)
    }

    public var usedFormatted: String {
        return DiskStats.format(usedBytes)
    }

    public var purgeableFormatted: String {
        return DiskStats.format(purgeableBytes)
    }

    public var percentUsedFormatted: String {
        return String(format: "%%%.1f", usedFraction * 100.0)
    }

    public var percentFreeFormatted: String {
        return String(format: "%%%.1f", freeFraction * 100.0)
    }

    public static func format(_ bytes: Int64) -> String {
        formatterLock.lock()
        defer { formatterLock.unlock() }
        return sharedFormatter.string(fromByteCount: max(0, bytes))
    }

    public static func current(forPath path: String = "/") -> DiskStats {
        if let stats = statsForVolume(atPath: path), stats.totalBytes > 0 {
            return stats
        }
        if path != "/", let rootStats = statsForVolume(atPath: "/") {
            return rootStats
        }
        return DiskStats(
            volumePath: "/",
            totalBytes: 0,
            freeBytes: 0,
            importantAvailableBytes: 0,
            volumeName: "Macintosh HD",
            timestamp: Date()
        )
    }

    public static func statsForVolume(atPath path: String) -> DiskStats? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let url = URL(fileURLWithPath: path)
        guard let vals = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeNameKey
        ]) else {
            return nil
        }

        let total = Int64(vals.volumeTotalCapacity ?? 0)
        guard total > 0 else { return nil }

        let free = Int64(vals.volumeAvailableCapacity ?? 0)
        let important = vals.volumeAvailableCapacityForImportantUsage ?? free
        let name = vals.volumeName ?? (path == "/" ? "Macintosh HD" : url.lastPathComponent)

        return DiskStats(
            volumePath: path,
            totalBytes: total,
            freeBytes: max(0, free),
            importantAvailableBytes: max(0, important),
            volumeName: name,
            timestamp: Date()
        )
    }

    public static func mountedVolumes() -> [DiskStats] {
        let keys: [URLResourceKey] = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeNameKey,
            .volumeIsLocalKey,
            .volumeIsReadOnlyKey
        ]

        var results: [DiskStats] = []
        var seenPaths = Set<String>()

        if let root = statsForVolume(atPath: "/") {
            results.append(root)
            seenPaths.insert("/")
        }

        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []

        for url in urls {
            let path = url.path
            guard !seenPaths.contains(path) else { continue }
            guard let vals = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            // Salt okunur disk görüntülerini (DMG) atla, yerel ve yazılabilir diskleri göster
            if vals.volumeIsReadOnly == true { continue }
            if let stats = statsForVolume(atPath: path), stats.totalBytes > 0 {
                results.append(stats)
                seenPaths.insert(path)
            }
        }

        return results
    }
}
