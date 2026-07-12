import SwiftUI

struct DailyCheckInView: View {
    let store: RecordStore
    var compact = false

    @State private var draftTodoTitle = ""

    var body: some View {
        if store.folderDisplayName == nil {
            ContentUnavailableView {
                Label("先选一处安放今天", systemImage: "folder")
            } description: {
                Text("每日待办与回顾会保存在你亲自选择的本地文件夹。")
            } actions: {
                Button("选择文件夹…") {
                    _ = store.selectFolder()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("DAYBREAK")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("在今天开始之前")
                            .font(compact ? .title3.weight(.semibold) : .title2.weight(.semibold))
                        Text("回望昨天的余响，再决定今天想留下什么。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    yesterdayEcho
                    todayPlan

                    Button("开始今天") {
                        store.confirmToday()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityHint("确认后即可使用计时与今日待办功能")
                }
                .padding(compact ? 1 : 20)
            }
            .scrollIndicators(.automatic)
        }
    }

    private var yesterdayEcho: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Yesterday’s Echo", systemImage: "moon.stars")
                .font(.callout.weight(.semibold))

            if store.yesterdayTodos.isEmpty {
                Text("昨天没有留下待办。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                if !store.yesterdayCompletedTodos.isEmpty {
                    Text("已完成")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    ForEach(store.yesterdayCompletedTodos) { todo in
                        HStack(spacing: 7) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(todo.title)
                                .strikethrough()
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .font(.caption)
                    }
                }

                if !store.yesterdayPendingTodos.isEmpty {
                    Text("尚未完成")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, store.yesterdayCompletedTodos.isEmpty ? 0 : 2)
                    ForEach(store.yesterdayPendingTodos) { todo in
                        HStack(spacing: 8) {
                            Text(todo.title)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if store.carriedYesterdayTodoIDs.contains(todo.id) {
                                Label("已带入", systemImage: "arrow.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            } else {
                                Button("带到今天") {
                                    store.carryYesterdayTodo(id: todo.id)
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                            }
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("昨天回顾")
    }

    private var todayPlan: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Today, at Your Pace", systemImage: "sun.max")
                .font(.callout.weight(.semibold))
            Text("可以写下待办，也可以让今天暂时留白。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField("为今天加一件事", text: $draftTodoTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTodo)
                Button("添加", action: addTodo)
                    .buttonStyle(.bordered)
                    .disabled(draftTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if store.todos.isEmpty {
                Text("今天留白。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.todos) { todo in
                    HStack(spacing: 8) {
                        Text(todo.title)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Button("移除") {
                            store.removeTodo(id: todo.id)
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("移除待办：\(todo.title)")
                    }
                    .font(.caption)
                }
            }
        }
    }

    private func addTodo() {
        let trimmedTitle = draftTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        store.addTodo(title: trimmedTitle)
        draftTodoTitle = ""
    }
}
