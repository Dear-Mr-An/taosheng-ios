import Foundation

/// 把本机录音打成一个 zip 分享出去。
///
/// iOS 没有系统级 zip API，这里写一个最小的 store（不压缩）打包器：
/// wav 已经是 PCM，再压缩也省不了多少，能装进一个文件就够了。
enum AudioExport {
    enum ExportError: LocalizedError {
        case empty
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .empty: return "本机还没有录音文件"
            case .writeFailed: return "打包失败，请重试"
            }
        }
    }

    /// 打包最近的录音，返回临时文件 URL
    static func zipAudio(limit: Int = 200) throws -> URL {
        let dir = Store.audioDir
        let all = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let files = all
            .filter { $0.pathExtension.lowercased() == "wav" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .prefix(limit)
        guard !files.isEmpty else { throw ExportError.empty }

        var entries: [(name: String, data: Data)] = []
        for f in files {
            guard let data = try? Data(contentsOf: f) else { continue }
            entries.append((f.lastPathComponent, data))
        }
        guard !entries.isEmpty else { throw ExportError.empty }

        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd-HHmm"
        let name = "涛声录音-\(stamp.string(from: Date())).zip"
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try makeZip(entries).write(to: out, options: .atomic)
        } catch {
            throw ExportError.writeFailed
        }
        return out
    }

    // MARK: - 最小 zip

    private static func makeZip(_ entries: [(name: String, data: Data)]) -> Data {
        var out = Data()
        var central = Data()
        var offset: UInt32 = 0
        // 固定时间戳：1980-01-01 00:00（zip 的最早合法时间）
        let dosTime: UInt16 = 0
        let dosDate: UInt16 = 0x0021

        for e in entries {
            let nameBytes = Array(e.name.utf8)
            let crc = crc32(e.data)
            let size = UInt32(e.data.count)
            let localOffset = offset

            // local file header
            out.append(uint32: 0x04034b50)
            out.append(uint16: 20)          // version needed
            out.append(uint16: 0x0800)      // UTF-8 文件名
            out.append(uint16: 0)           // method: store
            out.append(uint16: dosTime)
            out.append(uint16: dosDate)
            out.append(uint32: crc)
            out.append(uint32: size)
            out.append(uint32: size)
            out.append(uint16: UInt16(nameBytes.count))
            out.append(uint16: 0)           // extra len
            out.append(contentsOf: nameBytes)
            out.append(e.data)
            offset += UInt32(30 + nameBytes.count) + size

            // central directory
            central.append(uint32: 0x02014b50)
            central.append(uint16: 20)      // version made by
            central.append(uint16: 20)      // version needed
            central.append(uint16: 0x0800)
            central.append(uint16: 0)
            central.append(uint16: dosTime)
            central.append(uint16: dosDate)
            central.append(uint32: crc)
            central.append(uint32: size)
            central.append(uint32: size)
            central.append(uint16: UInt16(nameBytes.count))
            central.append(uint16: 0)       // extra
            central.append(uint16: 0)       // comment
            central.append(uint16: 0)       // disk
            central.append(uint16: 0)       // internal attrs
            central.append(uint32: 0)       // external attrs
            central.append(uint32: localOffset)
            central.append(contentsOf: nameBytes)
        }

        let centralOffset = offset
        out.append(central)
        out.append(uint32: 0x06054b50)
        out.append(uint16: 0)
        out.append(uint16: 0)
        out.append(uint16: UInt16(entries.count))
        out.append(uint16: UInt16(entries.count))
        out.append(uint32: UInt32(central.count))
        out.append(uint32: centralOffset)
        out.append(uint16: 0)
        return out
    }

    private static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 {
            c = (c & 1) == 1 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
        }
        return c
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for b in data {
            c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8)
        }
        return c ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func append(uint16 v: UInt16) {
        append(UInt8(v & 0xFF))
        append(UInt8((v >> 8) & 0xFF))
    }

    mutating func append(uint32 v: UInt32) {
        append(UInt8(v & 0xFF))
        append(UInt8((v >> 8) & 0xFF))
        append(UInt8((v >> 16) & 0xFF))
        append(UInt8((v >> 24) & 0xFF))
    }
}
