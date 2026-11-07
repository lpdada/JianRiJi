import XCTest
@testable import JianRiJi

/// `.voicepack` 解析与安装的单测。
/// 格式由 `tools/voice/gen_pack.py` 产出，App 端只用 Foundation 解开。
final class VoicePackFormatTests: XCTestCase {

    // MARK: - 构造测试包

    private func be16(_ value: UInt16) -> [UInt8] {
        withUnsafeBytes(of: value.bigEndian) { Array($0) }
    }

    private func be32(_ value: UInt32) -> [UInt8] {
        withUnsafeBytes(of: value.bigEndian) { Array($0) }
    }

    private func makePack(
        entries: [(key: String, payload: [UInt8])],
        version: UInt16 = 1,
        magic: String = "JRJP"
    ) -> Data {
        var payload = Data()
        var manifestEntries: [[String: Any]] = []
        for entry in entries {
            manifestEntries.append([
                "key": entry.key,
                "offset": payload.count,
                "length": entry.payload.count,
                "ext": "mp3",
            ])
            payload.append(contentsOf: entry.payload)
        }

        let manifest: [String: Any] = [
            "version": 1,
            "pack": "test",
            "title": "测试包",
            "voice": "ja-JP-NanamiNeural",
            "rate": "-10%",
            "count": entries.count,
            "generated_at": "2026-01-01T00:00:00Z",
            "entries": manifestEntries,
        ]
        let manifestData = try! JSONSerialization.data(withJSONObject: manifest, options: [])

        var data = Data()
        data.append(Data(magic.utf8))
        data.append(contentsOf: be16(version))
        data.append(contentsOf: be32(UInt32(manifestData.count)))
        data.append(manifestData)
        data.append(payload)
        return data
    }

    // MARK: - 解析

    func testParseValidPack() throws {
        let pack = makePack(entries: [
            ("w-a", [0xFF, 0xFB, 0x90, 0x00]),
            ("w-b", [0xFF, 0xFB, 0x90, 0x11]),
        ])
        let (manifest, payloadStart) = try VoicePackInstaller.parseManifest(pack)

        XCTAssertEqual(manifest.pack, "test")
        XCTAssertEqual(manifest.count, 2)
        XCTAssertEqual(manifest.voice, "ja-JP-NanamiNeural")
        XCTAssertEqual(manifest.rate, "-10%")
        XCTAssertEqual(manifest.entries.count, 2)
        XCTAssertEqual(manifest.entries[0].key, "w-a")
        XCTAssertEqual(manifest.entries[0].offset, 0)
        XCTAssertEqual(manifest.entries[0].length, 4)
        XCTAssertEqual(manifest.entries[1].offset, 4)
        XCTAssertEqual(payloadStart, pack.count - 8)
    }

    func testRejectBadMagic() {
        let pack = makePack(entries: [("w-a", [1, 2, 3, 4])], magic: "ZIPZ")
        XCTAssertThrowsError(try VoicePackInstaller.parseManifest(pack)) { error in
            guard case VoicePackFormatError.badMagic = error else {
                return XCTFail("应该报 badMagic，实际 \(error)")
            }
        }
    }

    func testRejectTooShort() {
        let data = Data([0x4A, 0x52])
        XCTAssertThrowsError(try VoicePackInstaller.parseManifest(data)) { error in
            guard case VoicePackFormatError.tooShort = error else {
                return XCTFail("应该报 tooShort，实际 \(error)")
            }
        }
    }

    func testRejectFutureVersion() {
        let pack = makePack(entries: [("w-a", [1, 2, 3, 4])], version: 9)
        XCTAssertThrowsError(try VoicePackInstaller.parseManifest(pack)) { error in
            guard case VoicePackFormatError.unsupportedVersion(let v) = error, v == 9 else {
                return XCTFail("应该报 unsupportedVersion(9)，实际 \(error)")
            }
        }
    }

    func testRejectTruncatedManifest() {
        var pack = makePack(entries: [("w-a", [1, 2, 3, 4])])
        // 把头 10 字节留下，后面砍掉
        pack = pack.prefix(10)
        XCTAssertThrowsError(try VoicePackInstaller.parseManifest(pack))
    }

    func testRejectTruncatedPayload() throws {
        var pack = makePack(entries: [("w-a", [1, 2, 3, 4])])
        // 砍掉最后两个字节，payload 就短了
        pack = pack.dropLast(2)
        XCTAssertThrowsError(try VoicePackInstaller.install(pack, packID: "unittest-truncated")) { error in
            guard case VoicePackFormatError.truncatedPayload = error else {
                return XCTFail("应该报 truncatedPayload，实际 \(error)")
            }
        }
        // 失败时不该留下清单
        XCTAssertFalse(VoicePackInstaller.installedPackIDs().contains("unittest-truncated"))
    }

    // MARK: - 安装 / 卸载

    func testInstallWritesFilesAndRegistry() throws {
        let packID = "unittest-install"
        defer {
            VoicePackInstaller.uninstall(packID: packID)
        }

        let pack = makePack(entries: [
            ("w-unittest-one", [0xFF, 0xFB, 0x90, 0x01]),
            ("w-unittest-two", [0xFF, 0xFB, 0x90, 0x02]),
        ])

        let count = try VoicePackInstaller.install(pack, packID: packID)
        XCTAssertEqual(count, 2)

        // 音频真的落地了
        XCTAssertTrue(VoicePack.has("w-unittest-one"))
        XCTAssertTrue(VoicePack.has("w-unittest-two"))
        XCTAssertEqual(VoicePack.url(for: "w-unittest-one")?.pathExtension, "mp3")

        // 清单也记下了，卸载时靠它
        XCTAssertTrue(VoicePackInstaller.installedPackIDs().contains(packID))
        let manifest = VoicePackInstaller.installedManifest(packID: packID)
        XCTAssertEqual(manifest?.count, 2)
    }

    func testUninstallRemovesFiles() throws {
        let packID = "unittest-uninstall"
        let pack = makePack(entries: [("w-unittest-gone", [0xFF, 0xFB, 0x90, 0x03])])
        try VoicePackInstaller.install(pack, packID: packID)
        XCTAssertTrue(VoicePack.has("w-unittest-gone"))

        VoicePackInstaller.uninstall(packID: packID)
        XCTAssertFalse(VoicePack.has("w-unittest-gone"))
        XCTAssertFalse(VoicePackInstaller.installedPackIDs().contains(packID))
    }

    // MARK: - 空包

    func testEmptyEntriesInstallIsHarmless() throws {
        let packID = "unittest-empty"
        defer { VoicePackInstaller.uninstall(packID: packID) }
        let pack = makePack(entries: [])
        let count = try VoicePackInstaller.install(pack, packID: packID)
        XCTAssertEqual(count, 0)
    }
}
