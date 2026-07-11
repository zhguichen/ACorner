import AppKit
import SwiftUI

@main
struct ACornerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(store: appDelegate.store)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = RecordStore()
    private var floatingPanel: FloatingPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let model = TaskSessionModel(store: store)
        floatingPanel = FloatingPanelController(model: model)
        floatingPanel?.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

private struct SettingsView: View {
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
            Section {
                Text("一隅会将完成的任务写入你选择的文件夹中。")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
    }
}
