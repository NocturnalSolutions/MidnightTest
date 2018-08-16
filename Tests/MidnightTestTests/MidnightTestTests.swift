import XCTest
@testable import MidnightTest

final class MidnightTestTests: XCTestCase {
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        XCTAssertEqual(MidnightTest().text, "Hello, World!")
    }


    static var allTests = [
        ("testExample", testExample),
    ]
}
