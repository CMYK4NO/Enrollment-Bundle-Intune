import XCTest
@testable import EnrollmentBundleStudio

final class HexColorTests: XCTestCase {
    func testParsesValidColors() throws {
        let rgb = try XCTUnwrap(HexColor(hex: "#FF8000").components)
        XCTAssertEqual(rgb.red, 1, accuracy: 0.001)
        XCTAssertEqual(rgb.green, 128.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(rgb.blue, 0, accuracy: 0.001)
        XCTAssertTrue(HexColor(hex: "0a64d2").isValid)
    }

    func testRejectsInvalidColors() {
        for value in ["", "#FFF", "#GGGGGG", "+FFFFF", "#FFFFFFF", "red"] {
            XCTAssertFalse(HexColor(hex: value).isValid, value)
        }
    }

    func testFormatsAndClamps() {
        XCTAssertEqual(HexColor.from(red: 1, green: 0.5, blue: 0).hex, "#FF8000")
        XCTAssertEqual(HexColor.from(red: 2, green: -1, blue: 0.0).hex, "#FF0000")
    }

    func testEncodesAsPlainString() throws {
        let data = try JSONEncoder().encode(["color": HexColor(hex: "#123456")])
        XCTAssertEqual(String(data: data, encoding: .utf8), "{\"color\":\"#123456\"}")
    }
}
