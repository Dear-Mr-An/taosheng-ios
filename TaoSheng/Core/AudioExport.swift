import Foundation

/// 把本机录音打成一个 zip 分享出去。
///
/// iOS 没有系统级 zip API，这里写一个最小的 store（不压缩）打包器：
/// wav 已经是 PCM，再压缩也省不了多少，能装进一个文件就够了。
///
/// 关键点：**流式写盘**。早期版本把所有 wav 读进内存再拼 Data，
/// 200 段 16k/16bit 录音大约 2 GB，必然被系统杀掉；现在逐块读写，内存占用恒定。
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

    private static let chunk = 1 << 18   // 256 KB

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

        let name = "涛声录音-\(Fmt.df("yyyyMMdd-HHmm").string(from: Date())).zip"
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: out)
        guard FileManager.default.createFile(atPath: out.path, contents: nil) else {
            throw ExportError.writeFailed
        }
        let fh = try FileHandle(forWritingTo: out)
        defer { try? fh.close() }

        var central = Data()
        var offset: UInt32 = 0
        var written = 0

        for f in files {
            let size64 = (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            // 单个文件超过 3.7 GB 或空文件直接跳过（zip 32 位偏移装不下）
            guard size64 > 0, size64 < 0xF000_0000 else { continue }
            guard let crc = try? crc32(of: f) else { continue }
            let size = UInt32(size64)
            let nameBytes = Array(f.lastPathComponent.utf8)
            guard nameBytes.count < Int(UInt16.max) else { continue }
            let localOffset = offset

            var head = Data()
            head.append(uint32: 0x0403_4b50)
            head.append(uint16: 20)         // version needed
            head.append(uint16: 0x0800)     // UTF-8 文件名
            head.append(uint16: 0)          // method: store
            head.append(uint16: 0)          // dos time: 1980-01-01 00:00
            head.append(uint16: 0x0021)     // dos date
            head.append(uint32: crc)
            head.append(uint32: size)
            head.append(uint32: size)
            head.append(uint16: UInt16(nameBytes.count))
            head.append(uint16: 0)          // extra len
            head.append(contentsOf: nameBytes)
            try fh.write(contentsOf: head)

            let src = try FileHandle(forReadingFrom: f)
            while true {
                let data = src.readData(ofLength: chunk)
                if data.isEmpty { break }
                try fh.write(contentsOf: data)
            }
            try? src.close()

            central.append(uint32: 0x0201_4b50)
            central.append(uint16: 20)      // version made by
            central.append(uint16: 20)      // version needed
            central.append(uint16: 0x0800)
            central.append(uint16: 0)
            central.append(uint16: 0)
            central.append(uint16: 0x0021)
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

            offset += UInt32(30 + nameBytes.count) + size
            written += 1
        }

        guard written > 0 else { throw ExportError.empty }

        try fh.write(contentsOf: central)
        var end = Data()
        end.append(uint32: 0x0605_4b50)
        end.append(uint16: 0)
        end.append(uint16: 0)
        end.append(uint16: UInt16(written))
        end.append(uint16: UInt16(written))
        end.append(uint32: UInt32(central.count))
        end.append(uint32: offset)
        end.append(uint16: 0)
        try fh.write(contentsOf: end)
        return out
    }

    // MARK: - CRC32

    private static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 {
            c = (c & 1) == 1 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
        }
        return c
    }

    private static func crc32(of url: URL) throws -> UInt32 {
        let fh = try FileHandle(forReadingFrom: url)
        defer { try? fh.close() }
        var c: UInt32 = 0xFFFF_FFFF
        while true {
            let data = fh.readData(ofLength: chunk)
            if data.isEmpty { break }
            data.withUnsafeBytes { raw in
                for b in raw.bindMemory(to: UInt8.self) {
                    c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8)
                }
            }
        }
        return c ^ 0xFFFF_FFFF
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
