import XCTest
@testable import EnrollmentBundleStudio

final class PlaceholderTests: XCTestCase {
    private let values: [Placeholder: String] = [
        .companyName: "Contoso",
        .userName: "amorgan",
        .userFullName: "Alex Morgan",
        .computerName: "MBP-01",
        .computerModel: "Mac16,1",
        .serialNumber: "SERIAL1",
        .osVersion: "15.1",
        .osName: "Sequoia"
    ]

    func testResolvesAllPlaceholders() {
        let text = Placeholder.allCases.map { $0.token }.joined(separator: "|")
        XCTAssertEqual(
            PlaceholderResolver.resolve(text, values: values),
            "Contoso|amorgan|Alex Morgan|MBP-01|Mac16,1|SERIAL1|15.1|Sequoia"
        )
    }

    func testMatchingIsCaseInsensitive() {
        XCTAssertEqual(PlaceholderResolver.resolve("Hi {UserFullName}", values: values), "Hi Alex Morgan")
    }

    func testUnknownTokensAreLeftIntact() {
        XCTAssertEqual(PlaceholderResolver.resolve("{nope} {username}", values: values), "{nope} amorgan")
    }

    func testMissingValueLeavesToken() {
        XCTAssertEqual(PlaceholderResolver.resolve("{osname}", values: [:]), "{osname}")
    }

    func testReplacementIsSinglePass() {
        let tricky: [Placeholder: String] = [.userName: "{companyname}", .companyName: "Contoso"]
        XCTAssertEqual(PlaceholderResolver.resolve("{username}", values: tricky), "{companyname}")
    }

    func testAdjacentAndNestedBraces() {
        XCTAssertEqual(PlaceholderResolver.resolve("{{username}}", values: values), "{amorgan}")
        XCTAssertEqual(PlaceholderResolver.resolve("{a {username}", values: values), "{a amorgan")
        XCTAssertEqual(PlaceholderResolver.resolve("{}", values: values), "{}")
        XCTAssertEqual(PlaceholderResolver.resolve("{username", values: values), "{username")
    }

    func testUnicodeTextAroundTokens() {
        XCTAssertEqual(PlaceholderResolver.resolve("Grüße, {username} 👋", values: values), "Grüße, amorgan 👋")
    }

    func testPlaceholderDiscovery() {
        XCTAssertEqual(PlaceholderResolver.placeholders(in: "{osname} {OSNAME} {username}"), [.osName, .userName])
        XCTAssertEqual(PlaceholderResolver.unknownTokens(in: "{usrname} {username} {usrname}"), ["{usrname}"])
    }

    func testTokensAreLowercase() {
        for placeholder in Placeholder.allCases {
            XCTAssertEqual(placeholder.token, placeholder.token.lowercased())
        }
    }
}
