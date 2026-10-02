import Foundation

/// A single sender waits here. Signals are retained across the dequeue/wait boundary.
final class VNCOutboundWake: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = false
    private var generation: UInt64 = 0
    private var waiter: CheckedContinuation<Void, Never>?
    private var timer: Task<Void, Never>?
    func signal() { complete(expectedGeneration: nil) }
    private func complete(expectedGeneration: UInt64?) {
        let completion = lock.withLock { () -> (CheckedContinuation<Void, Never>?, Task<Void, Never>?) in
            if let expectedGeneration, expectedGeneration != generation { return (nil, nil) }
            guard let waiter else { pending = true; return (nil, nil) }
            let timer = self.timer
            self.waiter = nil
            self.timer = nil
            return (waiter, timer)
        }
        completion.1?.cancel()
        completion.0?.resume()
    }
    func wait(seconds: TimeInterval) async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                lock.withLock {
                    if pending || Task.isCancelled { pending = false; continuation.resume(); return }
                    generation &+= 1
                    let ticket = generation
                    waiter = continuation
                    timer = Task { [weak self] in
                        do { try await Task.sleep(nanoseconds: UInt64(max(0.000001, seconds) * 1e9)) }
                        catch { return }
                        self?.complete(expectedGeneration: ticket)
                    }
                }
            }
        } onCancel: { self.signal() }
    }
}
