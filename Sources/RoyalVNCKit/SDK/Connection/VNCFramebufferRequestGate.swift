#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Dispatch

/// Governs requests, not rendering. A waiting server must never accumulate requests.
/// The send loop owns the actual writes; receive and input callbacks only update this state.
final class VNCFramebufferRequestGate {
    private let lock = NSLock()
    private var pending = false
    private var outstanding = true // The handshake sends the first, full request.
    private var stopped = false
    private var lastRequest: UInt64 = 0
    private var lastInput: UInt64?

    func sentInitialRequest(at now: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        lock.lock()
        defer { lock.unlock() }
        lastRequest = now
    }

    func completedUpdate() {
        lock.lock()
        defer { lock.unlock() }
        outstanding = false
        pending = true
    }

    func noteInput(at now: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        lock.lock()
        defer { lock.unlock() }
        lastInput = now
    }

    func takeRequest(at now: UInt64 = DispatchTime.now().uptimeNanoseconds) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !stopped, pending, !outstanding else { return false }
        let active = lastInput.map { now >= $0 && now - $0 < 2_000_000_000 } ?? false
        let interval: UInt64 = active ? 100_000_000 : 500_000_000
        guard now >= lastRequest, now - lastRequest >= interval else { return false }
        pending = false
        outstanding = true
        lastRequest = now
        return true
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        stopped = true
        pending = false
    }
}
