import Foundation
import Network

enum ProbeResult {
    case reachable
    case serverError(Int)
    case unreachable
}

class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isConnected: Bool = true
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.sayit.network-monitor")

    private init() {}

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.isConnected = path.status == .satisfied
        }
        monitor.start(queue: queue)
    }

    func probeEndpoint(url: String, timeout: TimeInterval = 5, completion: @escaping (ProbeResult) -> Void) {
        guard let url = URL(string: url) else {
            completion(.unreachable)
            return
        }

        performProbe(url: url, timeout: timeout, attempt: 0, maxAttempts: 1, completion: completion)
    }

    private func performProbe(url: URL, timeout: TimeInterval, attempt: Int, maxAttempts: Int, completion: @escaping (ProbeResult) -> Void) {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            if let error = error {
                if attempt < maxAttempts {
                    dbg("[NetworkMonitor] 探针失败 (第\(attempt + 1)次): \(error.localizedDescription)，1秒后重试")
                    DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                        self?.performProbe(url: url, timeout: timeout, attempt: attempt + 1, maxAttempts: maxAttempts, completion: completion)
                    }
                    return
                }
                completion(.unreachable)
                return
            }
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200...399).contains(statusCode) {
                completion(.reachable)
            } else {
                completion(.serverError(statusCode))
            }
        }.resume()
    }
}
