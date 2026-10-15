import Foundation
import XCTest
@testable import RoyalVNCKit

final class ARDKeyAgreementTests: XCTestCase {
    private struct Fixture: Decodable {
        let prime: String, `private`: String, peer: String, `public`: String, shared: String
    }
    private func bytes(_ hex: String) -> Data {
        let values = Array(hex)
        return Data(stride(from: 0, to: values.count, by: 2).map {
            UInt8(String(values[$0...$0 + 1]), radix: 16)!
        })
    }
    func testLeadingZeroDHIntegersRetainTheAdvertisedWireWidth() throws {
        // Every public/shared value is below this small prime and necessarily needs padding.
        let agreement = try XCTUnwrap(VNCProtocol.ARDAuthentication.DiffieHellmanKeyAgreement(
            prime: Data([0,1,0,1]), generator: Data([0,2]), peerKey: Data([0,0,0,2]), keyLength: 4))
        XCTAssertEqual(agreement.privateKey.count, 4)
        XCTAssertEqual(agreement.publicKey.count, 4)
        XCTAssertEqual(agreement.secretKey.count, 4)
        XCTAssertEqual(agreement.publicKey, agreement.secretKey)
        XCTAssertEqual(agreement.publicKey.first, 0)
        XCTAssertNil(VNCProtocol.ARDAuthentication.DiffieHellmanKeyAgreement(
            prime: Data([0,1,0,1]), generator: Data([0,0]), peerKey: Data([0,0,0,2]), keyLength: 4))
    }

    func test4096BitPublicAndSharedKeysMatchIndependentPythonVectorsWithinStartupBudget() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "ard4096", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        let prime = try XCTUnwrap(BigNum(data: bytes(fixture.prime)))
        let exponent = try XCTUnwrap(BigNum(data: bytes(fixture.private)))
        let generator = try XCTUnwrap(BigNum(data: Data([2])))
        let peer = try XCTUnwrap(BigNum(data: bytes(fixture.peer)))
        let publicKey = BigNum(), sharedKey = BigNum()
        let started = ContinuousClock.now
        XCTAssertTrue(BigNum.modExp(y: publicKey, g: generator, x: exponent, p: prime))
        XCTAssertTrue(BigNum.modExp(y: sharedKey, g: peer, x: exponent, p: prime))
        let elapsed = started.duration(to: .now)
        XCTAssertEqual(publicKey.fixedWidthBigEndianData(length: 512), bytes(fixture.public))
        XCTAssertEqual(sharedKey.fixedWidthBigEndianData(length: 512), bytes(fixture.shared))
        XCTAssertLessThan(elapsed, .seconds(5), "Debug arithmetic must fit comfortably inside the 25-second login budget")
        print("ARD 4096-bit public + shared computation: \(elapsed)")
    }
}
