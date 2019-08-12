// The MIT License (MIT)
//
// Copyright (c) 2019 Alexander Grebenyuk (github.com/kean).

import XCTest
import Regex

class BackreferencesTests: XCTestCase {

    func testReturnsNumberOfCapturingGroups() throws {
        let pattern = #"(\w)\1"#
        let string = "trellis seerlatter summer hoarse lesser aardvark stunned"

        let regex = try Regex(pattern)
        let matches = regex.matches(in: string).map { $0.fullMatch }

        XCTAssertEqual(matches, ["ll", "ee", "tt", "mm", "ss", "aa", "nn"])
    }

    // MARK: Error Reporting

    func testThrowsNonExistentSubpattern() throws {
        XCTAssertThrowsError(try Regex("(a)\\2")) { error in
            guard let error = (error as? Regex.Error) else {
                return XCTFail("Unexpected error")
            }
            XCTAssertEqual(error.message, "The token '\\2' references a non-existent or invalid subpattern")
            XCTAssertEqual(error.index, 0)
        }
    }

    func testThrowsNonExistentSubpatternSubpatterns() throws {
        XCTAssertThrowsError(try Regex("ab\\1")) { error in
            guard let error = (error as? Regex.Error) else {
                return XCTFail("Unexpected error")
            }
            XCTAssertEqual(error.message, "The token '\\1' references a non-existent or invalid subpattern")
            XCTAssertEqual(error.index, 0) // TODO: pass index to expression info
        }
    }
}
