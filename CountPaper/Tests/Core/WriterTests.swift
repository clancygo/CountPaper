import XCTest
@testable import CountPaperCore

final class WriterTests: XCTestCase {
    func testReplacementPreservesSurroundingUTF16Text() {
        let source = "; before\n- coffee ☕ 18\n; after\n"
        let range = (source as NSString).range(of: "coffee ☕ 18")
        XCTAssertEqual(LedgerWriter.replacing(range, in: source, with: "tea 🍵 20"), "; before\n- tea 🍵 20\n; after\n")
        XCTAssertNil(LedgerWriter.replacing(NSRange(location: 999, length: 1), in: source, with: "x"))
    }
}
