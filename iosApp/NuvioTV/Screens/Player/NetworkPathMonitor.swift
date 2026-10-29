import Foundation
import Network

/// P4 (BUG-143): is there a usable network path right now? A failure seen while the path is
/// unsatisfied is `.offline` and is never remembered against the link. Started on first access
/// (`NuvioTVApp.init` touches it, so the first failure reads a real value); true until the first
/// update arrives.
nonisolated final class NetworkPathMonitor: @unchecked Sendable {
    static let shared = NetworkPathMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "media.nuvio.network-path", qos: .utility)
    private let lock = NSLock()
    private var _isSatisfied = true

    var isSatisfied: Bool { lock.lock(); defer { lock.unlock() }; return _isSatisfied }

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let satisfied = path.status == .satisfied
            self.lock.lock()
            let changed = satisfied != self._isSatisfied
            self._isSatisfied = satisfied
            self.lock.unlock()
            if changed { print("[Network] path \(satisfied ? "satisfied" : "unsatisfied (\(path.status))")") }
        }
        monitor.start(queue: queue)
    }
}
