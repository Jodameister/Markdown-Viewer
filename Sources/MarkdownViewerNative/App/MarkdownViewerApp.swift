import AppKit
import SwiftUI

@MainActor
final class MarkdownViewerApplicationDelegate: NSObject, NSApplicationDelegate {
    private var pendingURLs: [URL] = []
    var viewModel: AppViewModel?

    func connect(to viewModel: AppViewModel) {
        self.viewModel = viewModel
        flushPendingURLs()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else { return }

        if let viewModel {
            viewModel.openIncomingItems(fileURLs)
        } else {
            pendingURLs.append(contentsOf: fileURLs)
        }
    }

    private func flushPendingURLs() {
        guard let viewModel, !pendingURLs.isEmpty else { return }
        let urls = pendingURLs
        pendingURLs.removeAll()
        viewModel.openIncomingItems(urls)
    }
}

struct MarkdownViewerCommands: Commands {
    let viewModel: AppViewModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Öffnen…") {
                viewModel.openSources()
            }
            .keyboardShortcut("o", modifiers: [.command])
        }

        CommandMenu("Dokument") {
            Button("Neu laden") {
                viewModel.refreshNow()
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(viewModel.sources.isEmpty)

            Button("Im Finder zeigen") {
                viewModel.revealCurrentDocument()
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(viewModel.activeDocument == nil)

            Divider()

            Button("Vergrößern") {
                viewModel.adjustZoom(by: 0.1)
            }
            .keyboardShortcut("=", modifiers: [.command])
            .disabled(viewModel.activeDocument == nil)

            Button("Verkleinern") {
                viewModel.adjustZoom(by: -0.1)
            }
            .keyboardShortcut("-", modifiers: [.command])
            .disabled(viewModel.activeDocument == nil)

            Button("Tatsächliche Größe") {
                viewModel.resetZoom()
            }
            .keyboardShortcut("0", modifiers: [.command])
            .disabled(viewModel.activeDocument == nil)
        }
    }
}

@main
struct MarkdownViewerNativeApp: App {
    @NSApplicationDelegateAdaptor(MarkdownViewerApplicationDelegate.self) private var appDelegate
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .onAppear {
                    appDelegate.connect(to: viewModel)
                }
        }
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentMinSize)
        .commands {
            SidebarCommands()
            InspectorCommands()
            ToolbarCommands()
            MarkdownViewerCommands(viewModel: viewModel)
        }
    }
}
