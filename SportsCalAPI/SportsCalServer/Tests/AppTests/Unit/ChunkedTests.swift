@testable import App
import XCTest

/// Pins the chunking helper used to bound Redis MGET argument counts.
final class ChunkedTests: XCTestCase {
    func test_empty() {
        XCTAssertEqual([Int]().chunked(into: 3), [])
    }
    func test_smallerThanChunk() {
        XCTAssertEqual([1, 2].chunked(into: 5), [[1, 2]])
    }
    func test_exactMultiple() {
        XCTAssertEqual([1, 2, 3, 4].chunked(into: 2), [[1, 2], [3, 4]])
    }
    func test_remainder() {
        XCTAssertEqual([1, 2, 3, 4, 5].chunked(into: 2), [[1, 2], [3, 4], [5]])
    }
    func test_chunkOfOne() {
        XCTAssertEqual([1, 2, 3].chunked(into: 1), [[1], [2], [3]])
    }
    func test_zeroSize_returnsWhole() {
        XCTAssertEqual([1, 2, 3].chunked(into: 0), [[1, 2, 3]])
    }
}
