import Foundation
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    @Published var sources: [SourceRecord] = []
    @Published var documents: [MarkdownDocumentRecord] = []
    @Published var activeDocument: MarkdownDocumentRecord?
    @Published var selectedLibraryItemID: String?
    @Published var outline: [OutlineItem] = []
    @Published var selectedOutlineItemID: String?
    @Published var zoomLevel: Double = 1.0
    @Published var sidebarVisible: Bool = true
    @Published var inspectorVisible: Bool = true
    @Published var isRefreshing: Bool = false
    @Published var errorMessage: String?
    @Published var renderedHTML: String?
    @Published var outlineNavigationRequest: OutlineNavigationRequest?

    let fileManager = FileManager.default
    let persistenceURL: URL
    let launchConfiguration: LaunchConfiguration
    var contentSignature: String = ""
    var monitorTask: Task<Void, Never>?
    var outlineNavigationRevision: Int = 0

    var libraryItems: [LibraryItem] {
        Self.makeLibraryItems(from: sources, documents: documents)
    }

    var navigationTitle: String {
        activeDocument?.name ?? "Markdown Viewer"
    }

    init(launchConfiguration: LaunchConfiguration = LaunchConfiguration()) {
        self.launchConfiguration = launchConfiguration

        if launchConfiguration.isUITesting {
            let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("MarkdownViewerNativeUITests", isDirectory: true)
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            persistenceURL = directory.appendingPathComponent(UUID().uuidString + ".json")
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let directory = appSupport.appendingPathComponent("MarkdownViewerNative", isDirectory: true)
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            persistenceURL = directory.appendingPathComponent("state.json")
        }

        if let fixtureRoot = launchConfiguration.fixtureRoot {
            sources = Self.makeSources(from: [fixtureRoot])
            Task { await refreshLibrary(preferredPath: nil) }
        } else {
            restoreState()
            if !launchConfiguration.isUITesting {
                startMonitoring()
            }
        }
    }

    deinit {
        monitorTask?.cancel()
    }
}
