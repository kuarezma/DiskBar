import Foundation
import CoreServices

public class DiskWatcher {
    public typealias ChangeHandler = (DiskStats) -> Void
    
    private var streamRef: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.ugur.diskbar.watcher", qos: .utility)
    private var handler: ChangeHandler?
    private var lastFreeBytes: Int64 = 0
    private var lastCheckTime: TimeInterval = 0
    private let throttleInterval: TimeInterval = 0.8 // Maksimum saniyede 1 kontrol (CPU %0 standardı)
    
    public init() {}
    
    public func start(handler: @escaping ChangeHandler) {
        self.handler = handler
        self.lastFreeBytes = DiskStats.current().freeBytes
        
        let paths = ["/System/Volumes/Data"] as CFArray
        
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        
        let callback: FSEventStreamCallback = { stream, clientInfo, numEvents, eventPaths, eventFlags, eventIds in
            guard let clientInfo = clientInfo else { return }
            let watcher = Unmanaged<DiskWatcher>.fromOpaque(clientInfo).takeUnretainedValue()
            watcher.handleEvents()
        }
        
        // 0.8 saniyelik toplama (coalescing) penceresi: arka arkaya gelen yüzlerce disk yazmasını tek kontrolde birleştirir
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.8,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer)
        ) else {
            print("DiskWatcher: FSEventStream başlatılamadı.")
            return
        }
        
        self.streamRef = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }
    
    private func handleEvents() {
        let now = Date().timeIntervalSince1970
        guard (now - lastCheckTime) >= throttleInterval else { return }
        lastCheckTime = now
        
        let stats = DiskStats.current()
        let currentFree = stats.freeBytes
        
        // Sadece boş alanda gerçekten değişim olduğunda ana iş parçacığına bildir
        if currentFree != lastFreeBytes {
            lastFreeBytes = currentFree
            DispatchQueue.main.async { [weak self] in
                self?.handler?(stats)
            }
        }
    }
    
    public func stop() {
        if let stream = streamRef {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            streamRef = nil
        }
    }
    
    deinit {
        stop()
    }
}
