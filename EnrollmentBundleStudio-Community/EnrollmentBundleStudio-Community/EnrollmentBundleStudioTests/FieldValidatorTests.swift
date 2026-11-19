import XCTest
@testable import EnrollmentBundleStudio

final class FieldValidatorTests: XCTestCase {
    func testValidReverseDNS() {
        for value in ["com.company.enrollment.bundle", "com.example", "org.my-company.app2", "io.a.b.c.d"] {
            XCTAssertTrue(FieldValidator.isValidReverseDNS(value), value)
        }
    }

    func testInvalidReverseDNS() {
        let invalid = [
            "", "company", "com..bundle", ".com.bundle", "com.bundle.", "com.comp any.app",
            "com.-company.app", "com.company-.app", "1com.company", "com.company_name.app",
            "com.cömpany.app", "com/company/app", String(repeating: "a", count: 64) + ".com"
        ]
        for value in invalid {
            XCTAssertFalse(FieldValidator.isValidReverseDNS(value), value)
        }
        XCTAssertNotNil(FieldValidator.reverseDNSIssue("bad"))
        XCTAssertEqual(FieldValidator.reverseDNSIssue(""), "Required.")
        XCTAssertNil(FieldValidator.reverseDNSIssue("com.company.enrollment.bundle"))
    }

    func testValidVersions() {
        for value in ["1", "1.0", "1.0.0", "2026.11.14", "1.2.3.4", "0.0.1"] {
            XCTAssertTrue(FieldValidator.isValidVersion(value), value)
        }
    }

    func testInvalidVersions() {
        for value in ["", "1.", ".1", "1..0", "1.0.0-beta", "v1.0", "1.2.3.4.5", "1.0 ", "1234567890.0", "١.٠"] {
            XCTAssertFalse(FieldValidator.isValidVersion(value), value)
        }
    }

    func testURLValidation() {
        XCTAssertNil(FieldValidator.urlIssue(""))
        XCTAssertNil(FieldValidator.urlIssue("https://support.example.com/help"))
        XCTAssertNil(FieldValidator.urlIssue("http://intranet.example.com"))
        XCTAssertNotNil(FieldValidator.urlIssue("support.example.com"))
        XCTAssertNotNil(FieldValidator.urlIssue("ftp://example.com"))
        XCTAssertNotNil(FieldValidator.urlIssue("javascript:alert(1)"))
    }

    func testAbsolutePathValidation() {
        XCTAssertNil(FieldValidator.absolutePathIssue("/Library/Application Support/Company"))
        XCTAssertNotNil(FieldValidator.absolutePathIssue("Library/Company"))
        XCTAssertNotNil(FieldValidator.absolutePathIssue("/Library/../etc"))
    }
}
