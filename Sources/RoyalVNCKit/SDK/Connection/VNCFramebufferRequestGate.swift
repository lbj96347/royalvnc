#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Dispatch

public enum VNCFramebufferRequestPolicy: Sendable {
    case lowData, balanced, responsive
}

/// Governs requests, not rendering. A waiting server must never accumulate requests.
/// The send loop owns the actual writes; receive and input callbacks only update this state.
final class VNCFramebufferRequestGate {
    private let lock = NSLock()
    private var pending = false
    private var outstanding = true // The handshake sends the first, full request.
    private var stopped = false
    private var lastRequest: UInt64 = 0
    private var lastInput: UInt64?
    private var lastMotion: UInt64?

    func sentInitialRequest(at now: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        lock.lock()
        defer { lock.unlock() }
        lastRequest = now
    }

    func completedUpdate(hasPixelChanges: Bool = false, at now: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        lock.lock()
        defer { lock.unlock() }
        outstanding = false
        pending = true
        if hasPixelChanges { lastMotion = now }
    }

    func noteInput(at now: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        lock.lock()
        defer { lock.unlock() }
        lastInput = now
    }

    func takeRequest(policy: VNCFramebufferRequestPolicy = .lowData, at now: UInt64 = DispatchTime.now().uptimeNanoseconds) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !stopped, pending, !outstanding else { return false }
        let interval = requestInterval(policy: policy, at: now)
        guard now >= lastRequest, now - lastRequest >= interval else { return false }
        pending = false
        outstanding = true
        lastRequest = now
        return true
    }

    /// Preserve the input loop's 10 ms maximum sleep, but wake at an earlier picture deadline.
    func nextRequestDelay(policy: VNCFramebufferRequestPolicy, at now: UInt64 = DispatchTime.now().uptimeNanoseconds) -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        guard !stopped, pending, !outstanding, now >= lastRequest else { return 0.01 }
        let interval = requestInterval(policy: policy, at: now)
        let elapsed = now - lastRequest
        return elapsed >= interval ? 0 : min(0.01, Double(interval - elapsed) / 1_000_000_000)
    }

    private func requestInterval(policy: VNCFramebufferRequestPolicy, at now: UInt64) -> UInt64 {
        let active = lastInput.map { now >= $0 && now - $0 < 2_000_000_000 } ?? false
        let motion = policy == .balanced && (lastMotion.map { now >= $0 && now - $0 < 2_000_000_000 } ?? false)
        return (active || motion) ? (policy == .balanced ? 33_333_334 : 100_000_000) : 500_000_000
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        stopped = true
        pending = false
    }
}
