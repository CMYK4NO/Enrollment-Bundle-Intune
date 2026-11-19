import CommonCrypto
import CryptoKit
import Foundation

/// The fileEncryptionInfo Intune needs to decrypt the uploaded file (ProfileVersion1).
struct IntuneEncryptionInfo: Equatable {
    let encryptionKey: String
    let macKey: String
    let initializationVector: String
    let mac: String
    let fileDigest: String

    var json: [String: Any] {
        [
            "@odata.type": "microsoft.graph.fileEncryptionInfo",
            "encryptionKey": encryptionKey,
            "macKey": macKey,
            "initializationVector": initializationVector,
            "mac": mac,
            "profileIdentifier": "ProfileVersion1",
            "fileDigest": fileDigest,
            "fileDigestAlgorithm": "SHA256"
        ]
    }
}

struct IntuneEncryptedFile: Equatable {
    let info: IntuneEncryptionInfo
    let plainSize: Int64
    let encryptedSize: Int64
}

/// Encrypts a package the way Intune's app upload expects: AES-256-CBC with PKCS7 padding. The output file is
/// the 32-byte HMAC-SHA256 (over IV and ciphertext), then the 16-byte IV, then the ciphertext.
enum IntuneFileEncryptor {
    struct Keys {
        var encryptionKey: Data
        var macKey: Data
        var initializationVector: Data

        static func random() -> Keys {
            func bytes(_ size: SymmetricKeySize) -> Data { SymmetricKey(size: size).withUnsafeBytes { Data($0) } }
            return Keys(encryptionKey: bytes(.bits256), macKey: bytes(.bits256), initializationVector: bytes(.bits128))
        }
    }

    static func encrypt(source: URL, destination: URL, chunkSize: Int = 1 << 20, keys: Keys = .random()) throws -> IntuneEncryptedFile {
        guard keys.encryptionKey.count == 32, keys.macKey.count == 32, keys.initializationVector.count == 16 else {
            throw IntuneError.fileProblem("The encryption keys have the wrong size.")
        }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw IntuneError.fileProblem("The temporary encrypted file could not be created.")
        }
        let input = try FileHandle(forReadingFrom: source)
        let output = try FileHandle(forWritingTo: destination)
        defer {
            try? input.close()
            try? output.close()
        }

        var cryptorRef: CCCryptorRef?
        let created = keys.encryptionKey.withUnsafeBytes { key in
            keys.initializationVector.withUnsafeBytes { iv in
                CCCryptorCreate(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                                key.baseAddress, key.count, iv.baseAddress, &cryptorRef)
            }
        }
        guard created == Int32(kCCSuccess), let cryptor = cryptorRef else {
            throw IntuneError.fileProblem("The encryption could not be started.")
        }
        defer { CCCryptorRelease(cryptor) }

        var hmac = HMAC<SHA256>(key: SymmetricKey(data: keys.macKey))
        var digest = SHA256()
        try output.write(contentsOf: Data(count: 32)) // placeholder for the MAC, written last
        try output.write(contentsOf: keys.initializationVector)
        hmac.update(data: keys.initializationVector)

        var plainSize: Int64 = 0
        while let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty {
            plainSize += Int64(chunk.count)
            digest.update(data: chunk)
            var buffer = Data(count: CCCryptorGetOutputLength(cryptor, chunk.count, false))
            var produced = 0
            let capacity = buffer.count
            let status = buffer.withUnsafeMutableBytes { out in
                chunk.withUnsafeBytes { inBytes in
                    CCCryptorUpdate(cryptor, inBytes.baseAddress, chunk.count, out.baseAddress, capacity, &produced)
                }
            }
            guard status == Int32(kCCSuccess) else { throw IntuneError.fileProblem("The encryption failed.") }
            let part = buffer.prefix(produced)
            hmac.update(data: part)
            try output.write(contentsOf: part)
        }

        var tail = Data(count: CCCryptorGetOutputLength(cryptor, 0, true))
        var tailProduced = 0
        let tailCapacity = tail.count
        let finalStatus = tail.withUnsafeMutableBytes { out in
            CCCryptorFinal(cryptor, out.baseAddress, tailCapacity, &tailProduced)
        }
        guard finalStatus == Int32(kCCSuccess) else { throw IntuneError.fileProblem("The encryption could not be finished.") }
        let lastPart = tail.prefix(tailProduced)
        hmac.update(data: lastPart)
        try output.write(contentsOf: lastPart)

        let mac = Data(hmac.finalize())
        try output.seek(toOffset: 0)
        try output.write(contentsOf: mac)
        let encryptedSize = try output.seekToEnd()

        let info = IntuneEncryptionInfo(
            encryptionKey: keys.encryptionKey.base64EncodedString(),
            macKey: keys.macKey.base64EncodedString(),
            initializationVector: keys.initializationVector.base64EncodedString(),
            mac: mac.base64EncodedString(),
            fileDigest: Data(digest.finalize()).base64EncodedString()
        )
        return IntuneEncryptedFile(info: info, plainSize: plainSize, encryptedSize: Int64(encryptedSize))
    }
}
