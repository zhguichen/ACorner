import AppKit
import SwiftUI

@main
struct ACornerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(
                store: appDelegate.store,
                openMainPanel: {
                    appDelegate.showMainPanel()
                }
            )
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = RecordStore()
    private var model: TaskSessionModel?
    private var floatingPanel: FloatingPanelController?
    private var settingsWindow: NSWindow?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let model = TaskSessionModel(store: store)
        self.model = model
        floatingPanel = FloatingPanelController(
            model: model,
            store: store,
            openSettings: { [weak self] in
                self?.openSettingsWindow()
            }
        )
        observeSleepWake()
        floatingPanel?.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func observeSleepWake() {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        sleepObserver = notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.model?.pauseHourlyCheckInsForSleep()
            }
        }
        wakeObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.model?.resumeHourlyCheckInsAfterWake()
            }
        }
    }

    private func openSettingsWindow() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 500),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "一隅"
            window.contentView = NSHostingView(
                rootView: SettingsView(
                    store: store,
                    openMainPanel: { [weak self] in
                        self?.showMainPanel()
                    }
                )
            )
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }

        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func showMainPanel() {
        floatingPanel?.show()
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct SettingsView: View {
    let store: RecordStore
    let openMainPanel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                Button {
                    openMainPanel()
                } label: {
                    Label("主面板", systemImage: "rectangle.inset.filled")
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }

            if store.isTodayConfirmed {
                TabView {
                    TodoSettingsView(store: store)
                        .tabItem {
                            Label("待办", systemImage: "checklist")
                        }

                    DeadlineSettingsView(store: store)
                        .tabItem {
                            Label("期限", systemImage: "calendar")
                        }

                    StorageSettingsView(store: store)
                        .tabItem {
                            Label("记录", systemImage: "folder")
                        }
                }
            } else {
                DailyCheckInView(store: store)
            }
        }
        .frame(width: 560, height: 500)
    }
}

private struct TodoSettingsView: View {
    let store: RecordStore
    @State private var draftTodoTitle = ""
    @State private var recordPendingDeletion: TaskRecord?
    @State private var pastTodoPendingDeletion: PastTodoItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if store.folderDisplayName == nil {
                ContentUnavailableView {
                    Label("先选择保存位置", systemImage: "folder")
                } description: {
                    Text("待办和已完成状态会跟任务记录一起写入同一个本地文件夹。")
                } actions: {
                    Button("选择文件夹…") {
                        _ = store.selectFolder()
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("待办事项")
                        .font(.title3.weight(.semibold))
                    Text("完成后打勾，长条入口里的进度线会按完成数量逐步填满。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    TextField("新增一个待办事项", text: $draftTodoTitle)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addTodo)
                    Button("添加", action: addTodo)
                        .buttonStyle(.borderedProminent)
                        .disabled(draftTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                HStack {
                    Text("\(store.completedTodoCount)/\(store.todoCount) 已完成")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(store.folderDisplayName ?? "")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                List {
                    Section("待办") {
                        if store.pendingTodos.isEmpty {
                            Text("还没有待办事项")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(store.pendingTodos) { todo in
                                TodoRow(
                                    todo: todo,
                                    isCompleted: false,
                                    onToggle: { store.setTodoCompleted(id: todo.id, isCompleted: true) },
                                    onRemove: { store.removeTodo(id: todo.id) }
                                )
                            }
                        }
                    }

                    Section("已完成") {
                        if store.completedTodos.isEmpty {
                            Text("还没有已完成事项")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(store.completedTodos) { todo in
                                TodoRow(
                                    todo: todo,
                                    isCompleted: true,
                                    onToggle: { store.setTodoCompleted(id: todo.id, isCompleted: false) },
                                    onRemove: { store.removeTodo(id: todo.id) }
                                )
                            }
                        }
                    }

                    Section("过去未完成") {
                        if store.pastPendingTodos.isEmpty {
                            Text("没有过去未完成的待办")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(store.pastPendingTodos) { todo in
                                PastTodoRow(
                                    todo: todo,
                                    onAdd: { store.addPastTodo(id: todo.id) },
                                    onRemove: { pastTodoPendingDeletion = todo }
                                )
                            }
                        }
                    }

                    Section("完成记录") {
                        if store.recordDays.isEmpty {
                            Text("还没有完成记录")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(store.recordDays) { day in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(day.title)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    ForEach(day.records) { record in
                                        TaskRecordRow(record: record) {
                                            recordPendingDeletion = record
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(20)
        .confirmationDialog(
            "删除这条完成记录？",
            isPresented: Binding(
                get: { recordPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        recordPendingDeletion = nil
                    }
                }
            )
        ) {
            Button("删除", role: .destructive) {
                if let recordPendingDeletion {
                    store.removeRecord(recordPendingDeletion)
                }
                recordPendingDeletion = nil
            }
            Button("取消", role: .cancel) {
                recordPendingDeletion = nil
            }
        } message: {
            Text("这会从本地完成记录中永久删除该项。")
        }
        .confirmationDialog(
            "删除这条跨日待办？",
            isPresented: Binding(
                get: { pastTodoPendingDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        pastTodoPendingDeletion = nil
                    }
                }
            )
        ) {
            Button("删除所有未完成副本", role: .destructive) {
                if let pastTodoPendingDeletion {
                    store.deletePastTodoLineage(id: pastTodoPendingDeletion.id)
                }
                pastTodoPendingDeletion = nil
            }
            Button("取消", role: .cancel) {
                pastTodoPendingDeletion = nil
            }
        } message: {
            Text("这会删除这条事项在所有日期中未完成的副本；已完成的历史记录会保留。")
        }
    }

    private func addTodo() {
        let trimmedTitle = draftTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        store.addTodo(title: trimmedTitle)
        draftTodoTitle = ""
    }
}

private struct DeadlineSettingsView: View {
    let store: RecordStore
    @State private var draftTitle = ""
    @State private var dueDate = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if store.folderDisplayName == nil {
                ContentUnavailableView {
                    Label("先选择保存位置", systemImage: "folder")
                } description: {
                    Text("期限事项会和待办一起保存在同一个本地文件夹。")
                } actions: {
                    Button("选择文件夹…") {
                        _ = store.selectFolder()
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("期限事项")
                        .font(.title3.weight(.semibold))
                    Text("它们每天都可见；到期当天会标记为“今天截止”，不会弹窗打断你。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    TextField("例如：牙套更换", text: $draftTitle)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(addDeadline)
                    DatePicker("截止日期", selection: $dueDate, displayedComponents: .date)
                        .labelsHidden()
                    Button("添加", action: addDeadline)
                        .buttonStyle(.borderedProminent)
                        .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                List {
                    Section("待处理") {
                        if store.activeDeadlines.isEmpty {
                            Text("还没有期限事项")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(store.activeDeadlines) { deadline in
                                DeadlineRow(
                                    deadline: deadline,
                                    isCompleted: false,
                                    onToggle: { store.setDeadlineCompleted(id: deadline.id, isCompleted: true) },
                                    onRemove: { store.removeDeadline(id: deadline.id) }
                                )
                            }
                        }
                    }

                    Section("已完成") {
                        if store.completedDeadlines.isEmpty {
                            Text("还没有已完成期限事项")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(store.completedDeadlines) { deadline in
                                DeadlineRow(
                                    deadline: deadline,
                                    isCompleted: true,
                                    onToggle: { store.setDeadlineCompleted(id: deadline.id, isCompleted: false) },
                                    onRemove: { store.removeDeadline(id: deadline.id) }
                                )
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(20)
    }

    private func addDeadline() {
        let trimmedTitle = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        store.addDeadline(title: trimmedTitle, dueDate: dueDate)
        draftTitle = ""
    }
}

private struct PastTodoRow: View {
    let todo: PastTodoItem
    let onAdd: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(todo.title)
                Text("来自 \(todo.sourceDayKey)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button("加入今天", action: onAdd)
                .buttonStyle(.borderless)
                .accessibilityLabel("将待办加入今天：\(todo.title)")

            Button(action: onRemove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.tertiary)
            .accessibilityLabel("删除跨日待办：\(todo.title)")
        }
    }
}

private struct StorageSettingsView: View {
    let store: RecordStore

    var body: some View {
        Form {
            Section("记录") {
                LabeledContent("保存位置") {
                    Text(store.folderDisplayName ?? "尚未选择")
                        .foregroundStyle(store.folderDisplayName == nil ? .secondary : .primary)
                }
                Button("更改保存位置…") {
                    _ = store.selectFolder()
                }
            }

            Section("说明") {
                Text("一隅会将完成的任务记录和待办清单一起写入你选择的本地文件夹。")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}

private struct DeadlineRow: View {
    let deadline: DeadlineItem
    let isCompleted: Bool
    let onToggle: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(deadline.title)
                    .strikethrough(isCompleted)
                    .foregroundStyle(isCompleted ? .secondary : .primary)
                Text(isCompleted ? "已完成" : deadline.dueText())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.tertiary)
            .accessibilityLabel("删除期限事项：\(deadline.title)")
        }
    }
}

private struct TodoRow: View {
    let todo: TodoItem
    let isCompleted: Bool
    let onToggle: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(todo.title)
                    .strikethrough(isCompleted)
                    .foregroundStyle(isCompleted ? .secondary : .primary)
                Text(todo.completedAt ?? todo.createdAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button(action: onRemove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.tertiary)
        }
    }
}

private struct TaskRecordRow: View {
    let record: TaskRecord
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(record.title)
                    .font(.callout.weight(.medium))
                Spacer()
                Text(durationText(record.actualDuration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(action: onRemove) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.tertiary)
                .accessibilityLabel("删除完成记录：\(record.title)")
            }
            Text(record.completedAt, format: .dateTime.month().day().hour().minute())
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if !record.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(record.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

private func durationText(_ duration: TimeInterval) -> String {
    let roundedMinutes = max(1, Int((duration / 60).rounded()))
    return "约 \(roundedMinutes) 分钟"
}
