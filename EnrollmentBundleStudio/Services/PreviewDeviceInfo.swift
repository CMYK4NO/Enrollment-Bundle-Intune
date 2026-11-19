import Foundation
import SystemConfiguration

/// Values used to resolve placeholders in the static preview. Nothing here leaves the Mac.
struct PreviewDeviceInfo: Equatable {
    var values: [Placeholder: String]

    static func sample(organizationName: String) -> PreviewDeviceInfo {
        PreviewDeviceInfo(values: [
            .companyName: organizationName.isEmpty ? "Your Organization" : organizationName,
            .userName: "alex.morgan",
            .userFullName: "Alex Morgan",
            .computerName: "Alex's MacBook Pro",
            .computerModel: "Mac16,1",
            .serialNumber: "SAMPLE0SERIAL",
            .osVersion: "15.1",
            .osName: "Sequoia"
        ])
    }

    /// Values from this Mac. The serial number is deliberately not read for previews.
    static func currentMac(organizationName: String) -> PreviewDeviceInfo {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let versionString = version.patchVersion > 0
            ? "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
            : "\(version.majorVersion).\(version.minorVersion)"
        var computerName = "This Mac"
        if let name = SCDynamicStoreCopyComputerName(nil, nil) {
            computerName = name as String
        }
        return PreviewDeviceInfo(values: [
            .companyName: organizationName.isEmpty ? "Your Organization" : organizationName,
            .userName: NSUserName(),
            .userFullName: NSFullUserName(),
            .computerName: computerName,
            .computerModel: hardwareModel() ?? "Unknown model",
            .serialNumber: "Hidden in preview",
            .osVersion: versionString,
            .osName: marketingName(forMajorVersion: version.majorVersion)
        ])
    }

    static func marketingName(forMajorVersion major: Int) -> String {
        switch major {
        case 13: return "Ventura"
        case 14: return "Sonoma"
        case 15: return "Sequoia"
        case 26: return "Tahoe"
        default: return "macOS"
        }
    }

    private static func hardwareModel() -> String? {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        let model = String(decoding: bytes, as: UTF8.self)
        return model.isEmpty ? nil : model
    }
}
