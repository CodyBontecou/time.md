import XCTest
@testable import time_md

final class InputAggregatorTests: XCTestCase {

    // MARK: - Normalization

    func test_normalizeWord_keepsBasicWords() {
        XCTAssertEqual(InputAggregator.normalizeWord("hello"), "hello")
        XCTAssertEqual(InputAggregator.normalizeWord("World"), "world")
        XCTAssertEqual(InputAggregator.normalizeWord("café"), "café")
    }

    func test_normalizeWord_rejectsTooShort() {
        XCTAssertNil(InputAggregator.normalizeWord(""))
        XCTAssertNil(InputAggregator.normalizeWord("a"))
    }

    func test_normalizeWord_rejectsTooLong() {
        XCTAssertNil(InputAggregator.normalizeWord(String(repeating: "x", count: 25)))
    }

    func test_normalizeWord_rejectsDigitsAndSymbols() {
        // Mixed alphanumerics — looks like a password / token.
        XCTAssertNil(InputAggregator.normalizeWord("p4ssw0rd"))
        XCTAssertNil(InputAggregator.normalizeWord("token123"))
        XCTAssertNil(InputAggregator.normalizeWord("hi!"))
        XCTAssertNil(InputAggregator.normalizeWord("a@b.c"))
    }

    func test_normalizeWord_rejectsHexHashes() {
        XCTAssertNil(InputAggregator.normalizeWord("deadbeefcafebabe"))
        XCTAssertNil(InputAggregator.normalizeWord("0123456789abcdef"))
    }

    func test_normalizeWord_acceptsHyphenated() {
        XCTAssertEqual(InputAggregator.normalizeWord("re-run"), "re-run")
    }

    func test_normalizeWord_acceptsApostrophes() {
        XCTAssertEqual(InputAggregator.normalizeWord("don't"), "don't")
    }

    func test_normalizeWord_rejectsHighEntropy() {
        // 6 unique chars in 6 positions → entropy 2.58 — passes.
        XCTAssertNotNil(InputAggregator.normalizeWord("aabbcc"))
        // Generated random alphabetic — this should fail entropy check.
        XCTAssertNil(InputAggregator.normalizeWord("xkjqzwfvbpmh"))
    }

    func test_hourBucket_formatsLocalTime() {
        let ts: Double = 1_730_419_200  // 2024-11-01 00:00:00 UTC
        let bucket = InputAggregator.hourBucket(for: ts)
        // Should be `yyyy-MM-dd HH:00` in local timezone.
        XCTAssertTrue(bucket.hasSuffix(":00"))
        XCTAssertEqual(bucket.count, 16)
    }
}
