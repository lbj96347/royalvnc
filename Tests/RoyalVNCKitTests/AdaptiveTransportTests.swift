import XCTest
@testable import RoyalVNCKit

final class AdaptiveTransportTests: XCTestCase {
    func testAppleScalingWireFormatUsesBigEndianDouble() {
        XCTAssertEqual(VNCProtocol.AppleServerScale(scale: 0.5).data,
                       Data([8, 0, 0x3f, 0xe0, 0, 0, 0, 0, 0, 0]))
        XCTAssertEqual(VNCProtocol.AppleServerScale(scale: 1).data,
                       Data([8, 0, 0x3f, 0xf0, 0, 0, 0, 0, 0, 0]))
    }
    func testAdaptiveRearmsWithoutIdleDelayAndDoesNotStackRequests() {
        let gate = VNCFramebufferRequestGate()
        gate.sentInitialRequest(at: 0)
        XCTAssertFalse(gate.takeRequest(policy: .adaptive, at: 1_000_000_000))
        gate.completedUpdate(hasPixelChanges: true, at: 5_000_000_000)
        XCTAssertTrue(gate.takeRequest(policy: .adaptive, at: 5_000_000_000))
        XCTAssertFalse(gate.takeRequest(policy: .adaptive, at: 6_000_000_000))
        gate.completedUpdate(hasPixelChanges: true, at: 6_000_000_000)
        XCTAssertTrue(gate.takeRequest(policy: .adaptive, at: 6_000_000_000))
        gate.completedUpdate(hasPixelChanges: true, at: 6_010_000_000)
        XCTAssertFalse(gate.takeRequest(policy: .adaptive, at: 6_033_333_333))
        XCTAssertTrue(gate.takeRequest(policy: .adaptive, at: 6_033_333_334))
    }
    func testInputInterruptsEmptyUpdateBackoffWithoutDuplicatingOutstandingRequests() {
        let gate = VNCFramebufferRequestGate()
        gate.sentInitialRequest(at: 0)
        gate.completedUpdate(at: 1)
        gate.noteInput(at: 40_000_000)
        XCTAssertTrue(gate.takeRequest(policy: .adaptive, at: 40_000_000))
        gate.noteInput(at: 100_000_000)
        XCTAssertFalse(gate.takeRequest(policy: .adaptive, at: 100_000_000))
    }
    func testEmptyUpdatesBackOffAndStopCancelsPendingRequest() {
        let gate = VNCFramebufferRequestGate()
        gate.sentInitialRequest(at: 0)
        gate.completedUpdate(at: 1)
        XCTAssertFalse(gate.takeRequest(policy: .adaptive, at: 499_999_999))
        XCTAssertTrue(gate.takeRequest(policy: .adaptive, at: 500_000_000))
        gate.completedUpdate(hasPixelChanges: true, at: 600_000_000)
        gate.stop()
        XCTAssertFalse(gate.takeRequest(policy: .adaptive, at: 1_000_000_000))
    }
    func testOnlyAdjacentExplicitMovesCoalesceAndEdgesRemainOrdered() {
        let queue = Queue<Int>()
        queue.enqueue(1, replaceable: true)
        queue.enqueue(2, replaceable: true)
        queue.enqueue(3)
        queue.enqueue(4, replaceable: true)
        queue.enqueue(5, replaceable: true)
        queue.enqueue(6)
        XCTAssertEqual([queue.dequeue(), queue.dequeue(), queue.dequeue(), queue.dequeue()], [2, 3, 5, 6])
        XCTAssertNil(queue.dequeue())
    }
    func testWakeRetainsSignalBeforeWaitAndCancellationReturns() async {
        let wake = VNCOutboundWake()
        wake.signal()
        let clock = ContinuousClock()
        let start = clock.now
        await wake.wait(seconds: 10)
        XCTAssertLessThan(start.duration(to: clock.now), .seconds(1))
        let task = Task { await wake.wait(seconds: 10) }
        task.cancel()
        await task.value
    }
    func testWakeInterruptsSleepingSender() async {
        let wake = VNCOutboundWake()
        let clock = ContinuousClock()
        let start = clock.now
        let task = Task { await wake.wait(seconds: 10) }
        try? await Task.sleep(for: .milliseconds(10))
        wake.signal()
        await task.value
        XCTAssertLessThan(start.duration(to: clock.now), .seconds(1))
    }
}
