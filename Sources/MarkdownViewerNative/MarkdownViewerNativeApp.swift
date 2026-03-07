import AppKit
import Foundation
import QuickLookUI
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static var markdownDocument: UTType {
        UTType(filenameExtension: "md") ?? .plainText
    }
}

enum ThemePreference: String, CaseIterable, Codable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Hell"
        case .dark: "Dunkel"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum SourceKind: String, Codable {
    case folder
    case file
}

struct SourceRecord: Codable, Hashable, Identifiable {
    let id: String
    let kind: SourceKind
    let label: String
    let path: String
}

struct MarkdownDocumentRecord: Hashable, Identifiable {
    let id: String
    let sourceID: String
    let sourceKind: SourceKind
    let sourceLabel: String
    let path: String
    let directory: String
    let name: String
    let relativePath: String
    let contextPath: String
}

struct OutlineItem: Hashable, Identifiable {
    let id: String
    let title: String
    let level: Int
}

struct PersistedState: Codable {
    var sources: [SourceRecord]
    var activeDocumentPath: String?
    var zoomLevel: Double
    var themePreference: ThemePreference
    var sidebarVisible: Bool
    var inspectorVisible: Bool
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var sources: [SourceRecord] = []
    @Published var documents: [MarkdownDocumentRecord] = []
    @Published var activeDocument: MarkdownDocumentRecord?
    @Published var outline: [OutlineItem] = []
    @Published var zoomLevel: Double = 1.0
    @Published var themePreference: ThemePreference = .system
    @Published var sidebarVisible: Bool = true
    @Published var inspectorVisible: Bool = true
    @Published var isRefreshing: Bool = false
    @Published var lastUpdatedText: String?
    @Published var errorMessage: String?
    @Published var previewRevision: Int = 0

    private let fileManager = FileManager.default
    private var monitorTask: Task<Void, Never>?
    private let persistenceURL: URL
    private var contentSignature: String = ""

    init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = appSupport.appendingPathComponent("MarkdownViewerNative", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        persistenceURL = directory.appendingPathComponent("state.json")
        restoreState()
        startMonitoring()
    }

    deinit {
        monitorTask?.cancel()
    }

    func openFolders() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Öffnen"

        guard panel.runModal() == .OK else { return }

        let newSources = panel.urls.map {
            SourceRecord(
                id: "folder:\($0.path)",
                kind: .folder,
                label: $0.lastPathComponent,
                path: $0.path
            )
        }

        mergeSources(newSources)
    }

    func openFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.markdownDocument, .plainText]
        panel.prompt = "Öffnen"

        guard panel.runModal() == .OK else { return }

        let newSources = panel.urls
            .filter { Self.isMarkdownURL($0) }
            .map {
                SourceRecord(
                    id: "file:\($0.path)",
                    kind: .file,
                    label: $0.lastPathComponent,
                    path: $0.path
                )
            }

        mergeSources(newSources)
    }

    func removeSource(_ source: SourceRecord) {
        sources.removeAll { $0.id == source.id }
        Task { await refreshLibrary(preferredPath: activeDocument?.path) }
    }

    func selectDocument(_ document: MarkdownDocumentRecord) {
        activeDocument = document
        loadDocument(at: document.path)
        persistState()
    }

    func adjustZoom(by delta: Double) {
        zoomLevel = min(1.4, max(0.85, (zoomLevel + delta).rounded(toPlaces: 2)))
        persistState()
    }

    func resetZoom() {
        zoomLevel = 1.0
        persistState()
    }

    func refreshNow() {
        Task { await refreshLibrary(preferredPath: activeDocument?.path) }
    }

    func revealCurrentDocument() {
        guard let activeDocument else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: activeDocument.path)])
    }

    func setSidebarVisible(_ isVisible: Bool) {
        sidebarVisible = isVisible
        persistState()
    }

    func setInspectorVisible(_ isVisible: Bool) {
        inspectorVisible = isVisible
        persistState()
    }

    func setThemePreference(_ preference: ThemePreference) {
        themePreference = preference
        persistState()
    }

    private func mergeSources(_ newSources: [SourceRecord]) {
        var merged = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        for source in newSources {
            merged[source.id] = source
        }
        sources = merged.values.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
        Task { await refreshLibrary(preferredPath: activeDocument?.path) }
    }

    private func restoreState() {
        guard
            let data = try? Data(contentsOf: persistenceURL),
            let state = try? JSONDecoder().decode(PersistedState.self, from: data)
        else {
            return
        }

        sources = state.sources
        zoomLevel = min(1.4, max(0.85, state.zoomLevel))
        themePreference = state.themePreference
        sidebarVisible = state.sidebarVisible
        inspectorVisible = state.inspectorVisible

        Task {
            await refreshLibrary(preferredPath: state.activeDocumentPath)
        }
    }

    private func persistState() {
        let state = PersistedState(
            sources: sources,
            activeDocumentPath: activeDocument?.path,
            zoomLevel: zoomLevel,
            themePreference: themePreference,
            sidebarVisible: sidebarVisible,
            inspectorVisible: inspectorVisible
        )

        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: persistenceURL, options: .atomic)
    }

    private func startMonitoring() {
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !self.sources.isEmpty else { continue }
                let nextSignature = self.computeSignature()
                if nextSignature != self.contentSignature {
                    await self.refreshLibrary(preferredPath: self.activeDocument?.path)
                }
            }
        }
    }

    private func computeSignature() -> String {
        let parts = sources.flatMap { source -> [String] in
            if source.kind == .file {
                let url = URL(fileURLWithPath: source.path)
                let timestamp = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?
                    .timeIntervalSince1970 ?? 0
                return ["\(source.path)#\(timestamp)"]
            }

            return enumerateMarkdownURLs(at: URL(fileURLWithPath: source.path)).map { url in
                let timestamp = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?
                    .timeIntervalSince1970 ?? 0
                return "\(url.path)#\(timestamp)"
            }
        }
        return parts.sorted().joined(separator: "|")
    }

    private func enumerateMarkdownURLs(at rootURL: URL) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var urls: [URL] = []
        for case let url as URL in enumerator where Self.isMarkdownURL(url) {
            urls.append(url)
        }
        return urls.sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
    }

    private func refreshLibrary(preferredPath: String?) async {
        isRefreshing = true
        defer { isRefreshing = false }

        let nextDocuments = await Task.detached(priority: .userInitiated) { [sources] in
            Self.scanDocuments(from: sources)
        }.value

        documents = nextDocuments
        contentSignature = computeSignature()

        if let preferredPath, let preferred = nextDocuments.first(where: { $0.path == preferredPath }) {
            selectDocument(preferred)
        } else if let first = nextDocuments.first {
            selectDocument(first)
        } else {
            activeDocument = nil
            outline = []
            lastUpdatedText = nil
            errorMessage = nil
            persistState()
        }
    }

    private func loadDocument(at path: String) {
        let url = URL(fileURLWithPath: path)
        do {
            let markdown = try String(contentsOf: url, encoding: .utf8)
            outline = MarkdownOutlineParser.outline(from: markdown)
            let modificationDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            if let modificationDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .medium
                lastUpdatedText = formatter.string(from: modificationDate)
            } else {
                lastUpdatedText = nil
            }
            errorMessage = nil
            previewRevision &+= 1
        } catch {
            outline = []
            lastUpdatedText = nil
            errorMessage = error.localizedDescription
        }
        persistState()
    }

    nonisolated static func scanDocuments(from sources: [SourceRecord]) -> [MarkdownDocumentRecord] {
        var gatheredDocuments: [MarkdownDocumentRecord] = []

        for source in sources {
            switch source.kind {
            case .file:
                let url = URL(fileURLWithPath: source.path)
                guard isMarkdownURL(url) else { continue }
                gatheredDocuments.append(makeDocument(for: url, source: source, rootURL: url.deletingLastPathComponent()))
            case .folder:
                let rootURL = URL(fileURLWithPath: source.path)
                let manager = FileManager.default
                guard let enumerator = manager.enumerator(
                    at: rootURL,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) else {
                    continue
                }

                while let nextObject = enumerator.nextObject() {
                    guard let url = nextObject as? URL, isMarkdownURL(url) else { continue }
                    gatheredDocuments.append(makeDocument(for: url, source: source, rootURL: rootURL))
                }
            }
        }

        return gatheredDocuments.sorted(by: { lhs, rhs in
            if lhs.sourceLabel != rhs.sourceLabel {
                return lhs.sourceLabel.localizedCaseInsensitiveCompare(rhs.sourceLabel) == .orderedAscending
            }
            return lhs.relativePath.localizedCaseInsensitiveCompare(rhs.relativePath) == .orderedAscending
        })
    }

    nonisolated static func makeDocument(for url: URL, source: SourceRecord, rootURL: URL) -> MarkdownDocumentRecord {
        let relativePath = url.path.replacingOccurrences(of: rootURL.path + "/", with: "")
        let contextPath = url.deletingLastPathComponent().path == rootURL.path
            ? source.label
            : url.deletingLastPathComponent().path.replacingOccurrences(of: rootURL.path + "/", with: "")

        return MarkdownDocumentRecord(
            id: url.path,
            sourceID: source.id,
            sourceKind: source.kind,
            sourceLabel: source.label,
            path: url.path,
            directory: url.deletingLastPathComponent().path,
            name: url.lastPathComponent,
            relativePath: relativePath,
            contextPath: contextPath.isEmpty ? source.label : contextPath,
        )
    }

    nonisolated static func isMarkdownURL(_ url: URL) -> Bool {
        ["md", "markdown", "mdown", "mkd", "mkdn"].contains(url.pathExtension.lowercased())
    }
}

enum MarkdownOutlineParser {
    static func outline(from markdown: String) -> [OutlineItem] {
        markdown
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { line -> OutlineItem? in
                let text = String(line)
                guard let match = text.range(of: #"^(#{1,6})\s+(.+)$"#, options: .regularExpression) else {
                    return nil
                }

                let matched = String(text[match])
                let hashes = matched.prefix { $0 == "#" }
                let title = matched.dropFirst(hashes.count).trimmingCharacters(in: .whitespacesAndNewlines)
                let slug = title
                    .lowercased()
                    .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

                return OutlineItem(id: slug.isEmpty ? UUID().uuidString : slug, title: title, level: hashes.count)
            }
    }
}

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 250, ideal: 290)
        } detail: {
            DocumentDetailView(viewModel: viewModel)
        }
        .inspector(isPresented: Binding(
            get: { viewModel.inspectorVisible && !viewModel.outline.isEmpty },
            set: { viewModel.setInspectorVisible($0) }
        )) {
            OutlineView(viewModel: viewModel)
                .frame(minWidth: 220)
        }
        .preferredColorScheme(viewModel.themePreference.colorScheme)
        .tint(.orange)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
                    viewModel.setSidebarVisible(columnVisibility != .detailOnly)
                } label: {
                    Label("Bibliothek", systemImage: "sidebar.left")
                }

                Button {
                    viewModel.setInspectorVisible(!viewModel.inspectorVisible)
                } label: {
                    Label("Navigation", systemImage: "sidebar.right")
                }
                .disabled(viewModel.outline.isEmpty)
            }

            ToolbarItemGroup {
                Button {
                    viewModel.adjustZoom(by: -0.1)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }

                Button {
                    viewModel.resetZoom()
                } label: {
                    Label("\(Int(viewModel.zoomLevel * 100))%", systemImage: "textformat.size")
                }

                Button {
                    viewModel.adjustZoom(by: 0.1)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }

                Menu {
                    Picker(
                        "Darstellung",
                        selection: Binding(
                            get: { viewModel.themePreference },
                            set: { viewModel.setThemePreference($0) }
                        )
                    ) {
                        ForEach(ThemePreference.allCases) { theme in
                            Text(theme.title).tag(theme)
                        }
                    }
                } label: {
                    Label(viewModel.themePreference.title, systemImage: "circle.lefthalf.filled")
                }

                Button {
                    viewModel.openFolders()
                } label: {
                    Label("Ordner", systemImage: "folder.badge.plus")
                }

                Button {
                    viewModel.openFiles()
                } label: {
                    Label("Dateien", systemImage: "doc.badge.plus")
                }

                Button {
                    viewModel.refreshNow()
                } label: {
                    Label("Neu laden", systemImage: "arrow.clockwise")
                }
            }
        }
        .frame(minWidth: 1180, minHeight: 760)
        .onAppear {
            columnVisibility = viewModel.sidebarVisible ? .all : .detailOnly
        }
        .onChange(of: columnVisibility) { _, newValue in
            viewModel.setSidebarVisible(newValue != .detailOnly)
        }
    }
}

struct SidebarView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var expandedSourceIDs: Set<String> = []

    var body: some View {
        List {
            if viewModel.sources.isEmpty {
                ContentUnavailableView(
                    "Bibliothek starten",
                    systemImage: "books.vertical",
                    description: Text("Öffne einen Ordner oder einzelne Markdown-Dateien.")
                )
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.clear)
            } else {
                ForEach(viewModel.sources) { source in
                    Section {
                        DisclosureGroup(isExpanded: Binding(
                            get: { expandedSourceIDs.contains(source.id) || viewModel.sources.count == 1 },
                            set: { isExpanded in
                                if isExpanded {
                                    expandedSourceIDs.insert(source.id)
                                } else {
                                    expandedSourceIDs.remove(source.id)
                                }
                            }
                        )) {
                            ForEach(viewModel.documents.filter { $0.sourceID == source.id }) { document in
                                Button {
                                    viewModel.selectDocument(document)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(document.name)
                                            .font(.body.weight(viewModel.activeDocument?.id == document.id ? .semibold : .regular))
                                            .lineLimit(1)
                                        Text(document.contextPath)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(viewModel.activeDocument?.id == document.id ? Color.orange.opacity(0.18) : Color.clear)
                            }
                        } label: {
                            HStack {
                                Label(source.label, systemImage: source.kind == .folder ? "folder" : "doc.text")
                                Spacer()
                                Button {
                                    viewModel.removeSource(source)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Bibliothek")
    }
}

struct DocumentDetailView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Group {
            if let document = viewModel.activeDocument {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(document.name)
                                .font(.largeTitle.bold())
                            Text(document.relativePath)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 8) {
                            if let lastUpdatedText = viewModel.lastUpdatedText {
                                Label(lastUpdatedText, systemImage: "clock")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Button("Im Finder zeigen") {
                                viewModel.revealCurrentDocument()
                            }
                        }
                    }
                    .padding(24)

                    Divider()

                    if let errorMessage = viewModel.errorMessage {
                        ContentUnavailableView(
                            "Datei konnte nicht geladen werden",
                            systemImage: "exclamationmark.triangle",
                            description: Text(errorMessage)
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView([.horizontal, .vertical]) {
                            QuickLookPreview(url: URL(fileURLWithPath: document.path), revision: viewModel.previewRevision)
                                .frame(minWidth: 840 * viewModel.zoomLevel, minHeight: 900 * viewModel.zoomLevel)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .padding(20)
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "Keine Datei ausgewählt",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Öffne links einen Ordner oder einzelne Markdown-Dateien.")
                )
            }
        }
        .navigationTitle("Dokument")
    }
}

struct OutlineView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        List(viewModel.outline) { item in
            Text(item.title)
                .font(item.level <= 2 ? .body : .callout)
                .padding(.leading, CGFloat(max(0, item.level - 1) * 8))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .listStyle(.sidebar)
        .navigationTitle("Navigation")
    }
}

struct QuickLookPreview: NSViewRepresentable {
    let url: URL
    let revision: Int

    func makeNSView(context: Context) -> QLPreviewView {
        let preview = QLPreviewView(frame: .zero, style: .normal)!
        preview.shouldCloseWithWindow = true
        preview.autostarts = true
        preview.previewItem = url as NSURL
        return preview
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        nsView.previewItem = url as NSURL
        nsView.refreshPreviewItem()
    }
}

@main
struct MarkdownViewerNativeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1500, height: 940)
        .windowResizability(.contentMinSize)
    }
}
