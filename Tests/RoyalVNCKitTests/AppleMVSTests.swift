#if canImport(JavaScriptCore)
import Foundation
import XCTest
@testable import RoyalVNCKit

final class AppleMVSTests: XCTestCase {
    private func bits(_ value: String) -> Data {
        let values = value.filter { $0 == "0" || $0 == "1" }
        var data = Data(repeating: 0, count: (values.count + 7) / 8)
        for (index, bit) in values.enumerated() where bit == "1" { data[index / 8] |= 0x80 >> (index % 8) }
        return data
    }
    private let m = "01101101"
    private let mvs = "011011010111011001110011"
    private func full(_ types: String, _ body: String) -> Data {
        let header = bits("0" + types + m)
        let offset = 6 + header.count
        return Data([0,15,25,UInt8(offset >> 16),UInt8((offset >> 8) & 255),UInt8(offset & 255)]) + header + bits(body + m)
    }
    private func partial(_ body: String) -> Data { Data([1,14,19]) + bits(body + mvs) }
    private var baseline: Data {
        // Two flat DCT tiles: Y DC=10, neutral chroma. With default Q=16,
        // the mathematical output is 128 + (10*16)/8 = 148 in each channel.
        full("10110000", "000 00 00 11100101 0010 1")
    }
    private func decode(_ payload: Data, using decoder: AppleMVSDecoder, pixels: inout Data,
                        x: Int = 0, y: Int = 0, width: Int = 16, height: Int = 8,
                        canvasWidth: Int = 16, canvasHeight: Int = 8) throws -> Bool {
        try pixels.withUnsafeMutableBytes {
            try decoder.decode(payload, width: canvasWidth, height: canvasHeight, surface: $0.baseAddress!,
                               x: x, y: y, width: width, height: height)
        }
    }
    func testDCTBaselineAndProgressiveChromaRefinementThenCacheReuse() throws {
        let decoder = try AppleMVSDecoder()
        var pixels = Data(repeating: 0, count: 16 * 8 * 4)
        XCTAssertTrue(try decode(baseline, using: decoder, pixels: &pixels))
        XCTAssertEqual(Array(pixels[0..<4]), [148,148,148,255])
        XCTAssertEqual(Array(pixels[32..<36]), [148,148,148,255])
        // Refine Cr DC by one. Baseline Cr=0; Q=19 gives sample 130.
        let refine = partial("01 000000 10 1010 0 1010 00")
        XCTAssertTrue(try decode(refine, using: decoder, pixels: &pixels))
        XCTAssertEqual(Array(pixels[0..<4]), [148,147,151,255])
        XCTAssertEqual(Array(pixels[32..<36]), [148,148,148,255])
        // Only partial DCT tiles enter cache; slot 1 must reproduce the refinement.
        XCTAssertTrue(try decode(partial("00 110 0000000000000001"), using: decoder, pixels: &pixels))
        XCTAssertEqual(Array(pixels[32..<36]), [148,147,151,255])
        // Refinements always reference the full baseline, not the prior partial.
        XCTAssertTrue(try decode(partial("01 000000 0 1010 0 1010 00"), using: decoder, pixels: &pixels))
        XCTAssertEqual(Array(pixels[0..<4]), [148,148,148,255])
    }
    func testQuantizationAndSkipDoNotClaimPictureReadiness() throws {
        let decoder = try AppleMVSDecoder()
        var pixels = Data(repeating: 0, count: 512)
        XCTAssertFalse(try decode(Data([2]) + Data(repeating: 8, count: 128), using: decoder, pixels: &pixels))
        XCTAssertTrue(try decode(baseline, using: decoder, pixels: &pixels))
        XCTAssertEqual(Array(pixels[0..<4]), [138,138,138,255])
        XCTAssertFalse(try decode(partial("00 00"), using: decoder, pixels: &pixels))
    }
    func testUnalignedRectangleAndClippedEdgeTileLeaveSurroundingPixelsUntouched() throws {
        let decoder = try AppleMVSDecoder()
        var pixels = Data(repeating: 77, count: 32 * 16 * 4)
        XCTAssertTrue(try decode(baseline, using: decoder, pixels: &pixels, x: 9, y: 3,
                                 width: 13, height: 7, canvasWidth: 32, canvasHeight: 16))
        XCTAssertEqual(Array(pixels[((3 * 32 + 9) * 4)..<((3 * 32 + 9) * 4 + 4)]), [148,148,148,255])
        XCTAssertEqual(pixels[(3 * 32 + 8) * 4], 77)
        XCTAssertEqual(pixels[(10 * 32 + 9) * 4], 77)
    }
    func testMalformedPayloadsCacheMissAndGeometryAreRejected() throws {
        var pixels = Data(repeating: 0, count: 512)
        for payload in [Data(), Data([3]), Data([2,1]), Data([0,15,25,255,255,255]), partial("11 0 0000000000000001 00")] {
            XCTAssertThrowsError(try decode(payload, using: AppleMVSDecoder(), pixels: &pixels))
        }
        XCTAssertThrowsError(try decode(baseline, using: AppleMVSDecoder(), pixels: &pixels, x: 1))
        let decoder = try AppleMVSDecoder()
        XCTAssertTrue(try decode(baseline, using: decoder, pixels: &pixels))
        var corrupt = baseline
        corrupt[corrupt.count - 1] ^= 0x40
        XCTAssertThrowsError(try decode(corrupt, using: decoder, pixels: &pixels))
    }
    func testSolidWhiteAndBlackWhiteBitmap() throws {
        var pixels = Data(repeating: 0, count: 512)
        let decoder = try AppleMVSDecoder()
        XCTAssertTrue(try decode(full("00010000", ""), using: decoder, pixels: &pixels))
        XCTAssertEqual(pixels, Data(repeating: 255, count: 512))
        // Type 3, two tiles, row-selector all white in the first and second.
        XCTAssertTrue(try decode(full("01110000", "11111111 11111111"), using: decoder, pixels: &pixels))
        XCTAssertEqual(pixels, Data(repeating: 255, count: 512))
    }
}
#endif
