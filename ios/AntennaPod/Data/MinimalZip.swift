import Foundation

/// Minimal ZIP helper (STORE / method 0 only) for iOS JSON backups — no third-party dependency.
/// Exporter always writes STORE; importer accepts STORE. Re-zipping with Finder (DEFLATE) is not supported.
enum MinimalZip {
    enum ZipError: LocalizedError {
        case emptyArchive
        case invalidArchive
        case unsupportedCompression(UInt16)

        var errorDescription: String? {
            switch self {
            case .emptyArchive:
                return String(localized: "Backup archive is empty")
            case .invalidArchive:
                return String(localized: "Invalid or corrupt backup ZIP")
            case .unsupportedCompression(let method):
                return String(localized: "Unsupported ZIP compression (\(Int(method))). Use an AntennaPod iOS backup (STORE) or re-export from Settings.")
            }
        }
    }

    /// Write a ZIP with STORE (no compression) entries. Names use forward slashes, no leading slash.
    static func writeStoreArchive(entries: [(name: String, data: Data)], to url: URL) throws {
        guard !entries.isEmpty else { throw ZipError.emptyArchive }

        var localParts: [Data] = []
        var centralParts: [Data] = []
        var offset: UInt32 = 0

        for entry in entries {
            let nameData = Data(entry.name.utf8)
            let crc = crc32(entry.data)
            let size = UInt32(entry.data.count)

            var local = Data()
            local.appendUInt32(0x0403_4b50)
            local.appendUInt16(20)
            local.appendUInt16(0)
            local.appendUInt16(0) // STORE
            local.appendUInt16(0)
            local.appendUInt16(0)
            local.appendUInt32(crc)
            local.appendUInt32(size)
            local.appendUInt32(size)
            local.appendUInt16(UInt16(nameData.count))
            local.appendUInt16(0)
            local.append(nameData)
            local.append(entry.data)
            localParts.append(local)

            var central = Data()
            central.appendUInt32(0x0201_4b50)
            central.appendUInt16(20)
            central.appendUInt16(20)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt32(crc)
            central.appendUInt32(size)
            central.appendUInt32(size)
            central.appendUInt16(UInt16(nameData.count))
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt16(0)
            central.appendUInt32(0)
            central.appendUInt32(offset)
            central.append(nameData)
            centralParts.append(central)

            offset += UInt32(local.count)
        }

        var out = Data()
        for part in localParts { out.append(part) }
        let centralOffset = UInt32(out.count)
        var centralSize: UInt32 = 0
        for part in centralParts {
            out.append(part)
            centralSize += UInt32(part.count)
        }
        out.appendUInt32(0x0605_4b50)
        out.appendUInt16(0)
        out.appendUInt16(0)
        out.appendUInt16(UInt16(entries.count))
        out.appendUInt16(UInt16(entries.count))
        out.appendUInt32(centralSize)
        out.appendUInt32(centralOffset)
        out.appendUInt16(0)

        try out.write(to: url, options: .atomic)
    }

    /// Read STORE entries into name → data. Rejects DEFLATE and other methods.
    static func readArchive(from url: URL) throws -> [String: Data] {
        let data = try Data(contentsOf: url)
        guard data.count >= 22, let eocdOffset = findEOCD(in: data) else {
            throw ZipError.invalidArchive
        }
        let totalEntries = Int(readUInt16(data, eocdOffset + 10))
        let centralSize = Int(readUInt32(data, eocdOffset + 12))
        let centralOffset = Int(readUInt32(data, eocdOffset + 16))
        guard centralOffset >= 0, centralOffset + centralSize <= data.count else {
            throw ZipError.invalidArchive
        }

        var result: [String: Data] = [:]
        var cursor = centralOffset
        for _ in 0..<totalEntries {
            guard cursor + 46 <= data.count, readUInt32(data, cursor) == 0x0201_4b50 else {
                throw ZipError.invalidArchive
            }
            let method = readUInt16(data, cursor + 10)
            let compSize = Int(readUInt32(data, cursor + 20))
            let nameLen = Int(readUInt16(data, cursor + 28))
            let extraLen = Int(readUInt16(data, cursor + 30))
            let commentLen = Int(readUInt16(data, cursor + 32))
            let localHeaderOffset = Int(readUInt32(data, cursor + 42))
            let nameStart = cursor + 46
            guard nameStart + nameLen <= data.count else { throw ZipError.invalidArchive }
            let name = String(data: data.subdata(in: nameStart..<(nameStart + nameLen)), encoding: .utf8) ?? ""
            cursor = nameStart + nameLen + extraLen + commentLen

            guard method == 0 else { throw ZipError.unsupportedCompression(method) }
            guard localHeaderOffset + 30 <= data.count, readUInt32(data, localHeaderOffset) == 0x0403_4b50 else {
                throw ZipError.invalidArchive
            }
            let localNameLen = Int(readUInt16(data, localHeaderOffset + 26))
            let localExtraLen = Int(readUInt16(data, localHeaderOffset + 28))
            let payloadStart = localHeaderOffset + 30 + localNameLen + localExtraLen
            guard payloadStart + compSize <= data.count else { throw ZipError.invalidArchive }
            let payload = data.subdata(in: payloadStart..<(payloadStart + compSize))
            if !name.isEmpty, !name.hasSuffix("/") {
                result[name] = payload
            }
        }
        if result.isEmpty { throw ZipError.emptyArchive }
        return result
    }

    // MARK: - Internals

    private static func findEOCD(in data: Data) -> Int? {
        let minEOCD = 22
        guard data.count >= minEOCD else { return nil }
        let start = max(0, data.count - (minEOCD + 65_535))
        var i = data.count - minEOCD
        while i >= start {
            if readUInt32(data, i) == 0x0605_4b50 { return i }
            i -= 1
        }
        return nil
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            let idx = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = (crc >> 8) ^ crcTable[idx]
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static let crcTable: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()

    private static func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
