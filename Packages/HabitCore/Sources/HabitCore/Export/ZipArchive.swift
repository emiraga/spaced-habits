import Foundation

/// A minimal zip writer for the CSV export (DESIGN.md §11): stored entries (no compression), UTF-8 names,
/// a fixed 1980-01-01 timestamp so the same files zip to the same bytes. No third-party dependency.
enum ZipArchive {
    enum ArchiveError: Error, Equatable {
        /// Plain zip (not zip64) caps entry and archive sizes and entry counts.
        case tooLarge(String)
    }

    static func stored(_ files: [(name: String, data: Data)]) throws -> Data {
        var archive = Data()
        var directory = Data()
        guard files.count < 0xFFFF else { throw ArchiveError.tooLarge("\(files.count) files") }
        for file in files {
            let name = Data(file.name.utf8)
            guard let size = UInt32(exactly: file.data.count), let offset = UInt32(exactly: archive.count),
                  let nameLength = UInt16(exactly: name.count), size < .max, offset < .max
            else { throw ArchiveError.tooLarge(file.name) }
            let crc = crc32(file.data)
            // version needed 2.0, flags: UTF-8 names, method: stored, time 00:00, date 1980-01-01
            let common: [any FixedWidthInteger] = [
                UInt16(20), UInt16(0x0800), UInt16(0), UInt16(0), UInt16(0x0021), crc, size, size, nameLength,
                UInt16(0),
            ]
            archive.appendLittleEndian([UInt32(0x0403_4B50)] + common)
            archive.append(name)
            archive.append(file.data)
            // made by 2.0 (MS-DOS), comment length, disk number, internal and external attributes
            directory.appendLittleEndian(
                [UInt32(0x0201_4B50), UInt16(20)] + common + [UInt16(0), UInt16(0), UInt16(0), UInt32(0), offset]
            )
            directory.append(name)
        }
        guard let directoryOffset = UInt32(exactly: archive.count),
              let directorySize = UInt32(exactly: directory.count),
              directoryOffset < .max
        else { throw ArchiveError.tooLarge("archive") }
        archive.append(directory)
        let count = UInt16(files.count)
        archive.appendLittleEndian([
            UInt32(0x0605_4B50), UInt16(0), UInt16(0), count, count, directorySize, directoryOffset, UInt16(0),
        ])
        return archive
    }

    private static let crcTable: [UInt32] = (0 ..< 256).map { index in
        (0 ..< 8).reduce(UInt32(index)) { crc, _ in crc & 1 == 1 ? 0xEDB8_8320 ^ (crc >> 1) : crc >> 1 }
    }

    static func crc32(_ data: Data) -> UInt32 {
        ~data.reduce(~UInt32(0)) { crc, byte in crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
    }
}

private extension Data {
    mutating func appendLittleEndian(_ values: [any FixedWidthInteger]) {
        for value in values {
            appendLittleEndian(value)
        }
    }

    /// Generic, so the bytes are the integer's and not an existential box's.
    private mutating func appendLittleEndian(_ value: some FixedWidthInteger) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
