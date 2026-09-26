import Foundation

public struct DiskStats {
    public let totalBytes: Int64
    public let freeBytes: Int64
    public let importantAvailableBytes: Int64
    public let volumeName: String
    public let timestamp: Date
    
    public var usedBytes: Int64 {
        return max(0, totalBytes - freeBytes)
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
        // 10 GB altı veya %10'dan az
        return freeBytes < (10 * 1024 * 1024 * 1024) || freeFraction < 0.10
    }
    
    public var isCriticalSpace: Bool {
        // 5 GB altı veya %5'ten az
        return freeBytes < (5 * 1024 * 1024 * 1024) || freeFraction < 0.05
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
        let purgeable = max(0, importantAvailableBytes - freeBytes)
        return DiskStats.format(purgeable)
    }
    
    public var percentUsedFormatted: String {
        return String(format: "%%%.1f", usedFraction * 100.0)
    }
    
    public var percentFreeFormatted: String {
        return String(format: "%%%.1f", freeFraction * 100.0)
    }
    
    public static func format(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .decimal // macOS Finder & Sistem Ayarları standardı
        formatter.allowedUnits = [.useGB, .useTB, .useMB]
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: bytes)
    }
    
    public static func current() -> DiskStats {
        let url = URL(fileURLWithPath: "/")
        let vals = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeNameKey
        ])
        
        let total = Int64(vals?.volumeTotalCapacity ?? 0)
        let free = Int64(vals?.volumeAvailableCapacity ?? 0)
        let important = vals?.volumeAvailableCapacityForImportantUsage ?? free
        let name = vals?.volumeName ?? "Macintosh HD"
        
        return DiskStats(
            totalBytes: total,
            freeBytes: free,
            importantAvailableBytes: important,
            volumeName: name,
            timestamp: Date()
        )
    }
}
