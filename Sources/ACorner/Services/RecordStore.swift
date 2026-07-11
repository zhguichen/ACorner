import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class RecordStore {
    private enum Keys {
        static let folderBookmark = "recordsFolderBookmark"
    }

    private enum FileName {
        static let records = "ACornerTasks.json"
        static let todos = "ACornerTodos.json"
    }

    private(set) var folderURL: URL?
    private(set) var records: [TaskRecord] = []
    private(set) var todos: [TodoItem] = []

    init() {
        guard let bookmark = UserDefaults.standard.data(forKey: Keys.folderBookmark) else { return }
        var isStale = false
        folderURL = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
        reloadRecords()
        reloadTodos()
    }

    var folderDisplayName: String? { folderURL?.path }
    var completedRecords: [TaskRecord] {
        records.sorted { $0.completedAt > $1.completedAt }
    }
    var todoCount: Int { todos.count }
    var completedTodoCount: Int { todos.filter(\.isCompleted).count }
    var todoProgress: Double { TodoProgress.fraction(for: todos) }
    var pendingTodos: [TodoItem] {
        todos
            .filter { !$0.isCompleted }
            .sorted { $0.createdAt < $1.createdAt }
    }
    var completedTodos: [TodoItem] {
        todos
            .filter(\.isCompleted)
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

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
        reloadRecords()
        reloadTodos()
        return true
    }

    func save(_ record: TaskRecord) throws {
        guard let folderURL else { return }
        let url = folderURL.appendingPathComponent(FileName.records)
        var updatedRecords = try loadRecords(from: url)
        if let index = updatedRecords.firstIndex(where: { $0.id == record.id }) {
            updatedRecords[index] = record
        } else {
            updatedRecords.append(record)
        }
        updatedRecords.sort { $0.startedAt > $1.startedAt }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(updatedRecords).write(to: url, options: .atomic)
        records = updatedRecords
    }

    func presentWriteError(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.informativeText = "一隅无法写入本地数据。请在设置中确认保存位置后重试。"
        alert.runModal()
    }

    func addTodo(title: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, let folderURL else { return }
        mutateTodos(in: folderURL) { todos in
            todos.append(TodoItem(id: UUID(), title: trimmedTitle, createdAt: Date(), completedAt: nil))
        }
    }

    func setTodoCompleted(id: UUID, isCompleted: Bool) {
        guard let folderURL else { return }
        mutateTodos(in: folderURL) { todos in
            guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
            todos[index].completedAt = isCompleted ? Date() : nil
        }
    }

    func removeTodo(id: UUID) {
        guard let folderURL else { return }
        mutateTodos(in: folderURL) { todos in
            todos.removeAll { $0.id == id }
        }
    }

    func pendingTodo(matchingTitle title: String) -> TodoItem? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }
        return pendingTodos.first { $0.title == trimmedTitle }
    }

    private func loadRecords(from url: URL) throws -> [TaskRecord] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([TaskRecord].self, from: Data(contentsOf: url))
    }

    private func reloadRecords() {
        guard let folderURL else {
            records = []
            return
        }
        let url = folderURL.appendingPathComponent(FileName.records)
        do {
            records = try loadRecords(from: url)
        } catch {
            records = []
            presentWriteError(error)
        }
    }

    private func reloadTodos() {
        guard let folderURL else {
            todos = []
            return
        }
        let url = folderURL.appendingPathComponent(FileName.todos)
        do {
            todos = try loadTodos(from: url)
        } catch {
            todos = []
            presentWriteError(error)
        }
    }

    private func mutateTodos(in folderURL: URL, update: (inout [TodoItem]) -> Void) {
        var updatedTodos = todos
        update(&updatedTodos)
        do {
            try saveTodos(updatedTodos, to: folderURL.appendingPathComponent(FileName.todos))
            todos = updatedTodos
        } catch {
            presentWriteError(error)
        }
    }

    private func loadTodos(from url: URL) throws -> [TodoItem] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([TodoItem].self, from: Data(contentsOf: url))
    }

    private func saveTodos(_ todos: [TodoItem], to url: URL) throws {
        let sortedTodos = todos.sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
            if lhs.isCompleted {
                return (lhs.completedAt ?? .distantPast) > (rhs.completedAt ?? .distantPast)
            }
            return lhs.createdAt < rhs.createdAt
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(sortedTodos).write(to: url, options: .atomic)
    }
}
