import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import EnrollmentBundleStudio

enum TestSupportError: Error {
    case imageCreationFailed
}

enum TestSupport {
    /// A small, valid PNG generated in memory.
    static func makePNG(width: Int = 4, height: Int = 4) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TestSupportError.imageCreationFailed
        }
        context.setFillColor(red: 0.04, green: 0.39, blue: 0.82, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else {
            throw TestSupportError.imageCreationFailed
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
            throw TestSupportError.imageCreationFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TestSupportError.imageCreationFailed
        }
        return output as Data
    }

    /// A project with fixed dates so encode/decode round trips compare exactly.
    static func makeProject() -> EnrollmentProject {
        EnrollmentProject.makeDefault(now: Date(timeIntervalSince1970: 1_794_000_000))
    }

    static func projectJSONObject(_ project: EnrollmentProject) throws -> [String: Any] {
        let data = try ProjectCoding.encode(project)
        let object = try JSONSerialization.jsonObject(with: data)
        return (object as? [String: Any]) ?? [:]
    }

    static func data(fromJSONObject object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
