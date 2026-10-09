import Compression
import Foundation

enum CRC32 {
    private static let table: [UInt32] = {
        var t = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 {
                if c & 1 != 0 { c = 0xEDB8_8320 ^ (c >> 1) } else { c >>= 1 }
            }
            t[i] = c
        }
        return t
    }()

    static func checksum(_ bytes: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in bytes {
            let index = Int((c ^ UInt32(b)) & 0xFF)
            c = table[index] ^ (c >> 8)
        }
        return ~c
    }
}

private func le16(_ v: Int) -> [UInt8] {
    [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)]
}

private func le32(_ v: Int) -> [UInt8] {
    [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
}

/// Minimal ZIP writer (stored entries, no compression) — enough for OOXML packages.
struct ZipWriter {
    private var body: [UInt8] = []
    private var directory: [UInt8] = []
    private var count = 0

    mutating func add(_ name: String, _ content: String) {
        add(name, bytes: Array(content.utf8))
    }

    mutating func add(_ name: String, bytes: [UInt8]) {
        let nameBytes = Array(name.utf8)
        let crc = Int(CRC32.checksum(bytes))
        let offset = body.count
        let dosDate = 0x21  // 1980-01-01
        var local: [UInt8] = [0x50, 0x4B, 0x03, 0x04]
        local += le16(20) + le16(0x0800) + le16(0) + le16(0) + le16(dosDate)
        local += le32(crc) + le32(bytes.count) + le32(bytes.count)
        local += le16(nameBytes.count) + le16(0)
        body += local + nameBytes + bytes

        var entry: [UInt8] = [0x50, 0x4B, 0x01, 0x02]
        entry += le16(20) + le16(20) + le16(0x0800) + le16(0) + le16(0) + le16(dosDate)
        entry += le32(crc) + le32(bytes.count) + le32(bytes.count)
        entry += le16(nameBytes.count) + le16(0) + le16(0) + le16(0) + le16(0)
        entry += le32(0) + le32(offset)
        directory += entry + nameBytes
        count += 1
    }

    func finish() -> Data {
        var out = body
        let directoryOffset = out.count
        out += directory
        out += [0x50, 0x4B, 0x05, 0x06]
        out += le16(0) + le16(0) + le16(count) + le16(count)
        out += le32(directory.count) + le32(directoryOffset) + le16(0)
        return Data(out)
    }
}

/// Minimal ZIP reader (stored + deflate) backed by Apple's Compression framework.
struct ZipArchive {
    private struct Entry {
        var method: Int
        var compressedSize: Int
        var size: Int
        var offset: Int
    }

    private let bytes: [UInt8]
    private var entries: [String: Entry] = [:]

    init(data: Data) throws {
        bytes = [UInt8](data)
        let n = bytes.count
        guard n >= 22 else { throw ConversionError.invalidDocx("file is too small") }

        var eocd = -1
        var i = n - 22
        while i >= max(0, n - 22 - 65_535) {
            if bytes[i] == 0x50, bytes[i + 1] == 0x4B, bytes[i + 2] == 0x05, bytes[i + 3] == 0x06 {
                eocd = i
                break
            }
            i -= 1
        }
        guard eocd >= 0 else { throw ConversionError.invalidDocx("not a ZIP archive") }

        let total = ZipArchive.u16(bytes, eocd + 10)
        var p = ZipArchive.u32(bytes, eocd + 16)
        for _ in 0..<total {
            guard p + 46 <= n, ZipArchive.u32(bytes, p) == 0x0201_4B50 else {
                throw ConversionError.invalidDocx("corrupt ZIP directory")
            }
            let method = ZipArchive.u16(bytes, p + 10)
            let compressed = ZipArchive.u32(bytes, p + 20)
            let size = ZipArchive.u32(bytes, p + 24)
            let nameLength = ZipArchive.u16(bytes, p + 28)
            let extraLength = ZipArchive.u16(bytes, p + 30)
            let commentLength = ZipArchive.u16(bytes, p + 32)
            let offset = ZipArchive.u32(bytes, p + 42)
            guard p + 46 + nameLength <= n else { throw ConversionError.invalidDocx("corrupt ZIP directory") }
            let name = String(decoding: bytes[(p + 46)..<(p + 46 + nameLength)], as: UTF8.self)
            entries[name] = Entry(method: method, compressedSize: compressed, size: size, offset: offset)
            p += 46 + nameLength + extraLength + commentLength
        }
    }

    func data(for name: String) throws -> Data? {
        guard let e = entries[name] else { return nil }
        let n = bytes.count
        guard e.offset + 30 <= n, ZipArchive.u32(bytes, e.offset) == 0x0403_4B50 else {
            throw ConversionError.invalidDocx("corrupt entry \(name)")
        }
        let start = e.offset + 30 + ZipArchive.u16(bytes, e.offset + 26) + ZipArchive.u16(bytes, e.offset + 28)
        guard start + e.compressedSize <= n else { throw ConversionError.invalidDocx("truncated entry \(name)") }
        let raw = Array(bytes[start..<(start + e.compressedSize)])
        switch e.method {
        case 0:
            return Data(raw)
        case 8:
            if e.size == 0 { return Data() }
            var out = [UInt8](repeating: 0, count: e.size)
            let written = raw.withUnsafeBufferPointer { src -> Int in
                out.withUnsafeMutableBufferPointer { dst -> Int in
                    compression_decode_buffer(dst.baseAddress!, dst.count, src.baseAddress!, src.count, nil, COMPRESSION_ZLIB)
                }
            }
            guard written == e.size else { throw ConversionError.invalidDocx("could not decompress \(name)") }
            return Data(out)
        default:
            throw ConversionError.invalidDocx("unsupported compression in \(name)")
        }
    }

    private static func u16(_ b: [UInt8], _ i: Int) -> Int {
        Int(b[i]) | (Int(b[i + 1]) << 8)
    }

    private static func u32(_ b: [UInt8], _ i: Int) -> Int {
        Int(b[i]) | (Int(b[i + 1]) << 8) | (Int(b[i + 2]) << 16) | (Int(b[i + 3]) << 24)
    }
}
