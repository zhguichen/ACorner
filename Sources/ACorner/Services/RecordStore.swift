import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class RecordStore {
    private enum Keys {
        static let folderBookmark = "recordsFolderBookmark"
    }

    private(set) var folderURL: URL?

    init() {
        guard let bookmark = UserDefaults.standard.data(forKey: Keys.folderBookmark) else { return }
        var isStale = false
        folderURL = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
    }

    var folderDisplayName: String? { folderURL?.path }

    func ensureFolder() -> Bool {
        folderURL != nil || selectFolder()
    }

    @discardableResult
    func selectFolder() -> Bool {
        let panel = NSOpenPanel()
        panel.title = "选择一隅的记录保存位置"
        panel.message = "任务记录会持续保存在此文件夹中。"
        panel.prompt = "选择此文件夹"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        folderURL = url
        if let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(bookmark, forKey: Keys.folderBookmark)
        }
        return true
    }

    func save(_ record: TaskRecord) throws {
        guard let folderURL else { return }
        let url = folderURL.appendingPathComponent("ACornerTasks.json")
        var records = try loadRecords(from: url)
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
        } else {
            records.append(record)
        }
        records.sort { $0.startedAt > $1.startedAt }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(records).write(to: url, options: .atomic)
    }

    func presentWriteError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.informativeText = "一隅无法写入任务记录。请在设置中确认保存位置后重试。"
        alert.runModal()
    }

    private func loadRecords(from url: URL) throws -> [TaskRecord] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([TaskRecord].self, from: Data(contentsOf: url))
    }
}
