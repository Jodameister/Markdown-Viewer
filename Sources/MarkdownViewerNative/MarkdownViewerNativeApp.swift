import AppKit
import cmark_gfm
import cmark_gfm_extensions
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import WebKit

extension UTType {
    static var markdownDocument: UTType {
        UTType(filenameExtension: "md") ?? .plainText
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

struct LibraryItem: Hashable, Identifiable {
    enum Kind: Hashable {
        case sourceFolder(SourceRecord)
        case sourceDocument(SourceRecord, MarkdownDocumentRecord?)
        case folder(sourceID: String, relativePath: String)
        case document(MarkdownDocumentRecord)
    }

    let id: String
    let name: String
    let symbolName: String
    let kind: Kind
    let children: [LibraryItem]

    var document: MarkdownDocumentRecord? {
        switch kind {
        case let .sourceDocument(_, document):
            return document
        case let .document(document):
            return document
        default:
            return nil
        }
    }

    var source: SourceRecord? {
        switch kind {
        case let .sourceFolder(source):
            return source
        case let .sourceDocument(source, _):
            return source
        default:
            return nil
        }
    }

    var helpText: String? {
        source?.path ?? document?.path
    }

    var childItems: [LibraryItem]? {
        children.isEmpty ? nil : children
    }
}

struct OutlineItem: Hashable, Identifiable {
    let id: String
    let title: String
    let level: Int
}

struct OutlineNavigationRequest: Equatable {
    let id: String
    let revision: Int
}

struct PersistedState: Codable {
    var sources: [SourceRecord]
    var activeDocumentPath: String?
    var zoomLevel: Double
    var sidebarVisible: Bool
    var inspectorVisible: Bool
}

struct LaunchConfiguration {
    static let fixtureRootEnvironmentKey = "MARKDOWN_VIEWER_UI_TEST_FIXTURE_ROOT"
    static let openRootEnvironmentKey = "MARKDOWN_VIEWER_UI_TEST_OPEN_ROOT"
    static let uiTestingEnvironmentKey = "MARKDOWN_VIEWER_UI_TESTING"

    let isUITesting: Bool
    let fixtureRoot: URL?
    let openRoot: URL?

    init(processInfo: ProcessInfo = .processInfo) {
        let environment = processInfo.environment
        let fixturePath = environment[Self.fixtureRootEnvironmentKey]
        let openPath = environment[Self.openRootEnvironmentKey]

        isUITesting = environment[Self.uiTestingEnvironmentKey] == "1" || fixturePath != nil || openPath != nil
        fixtureRoot = fixturePath.map { URL(fileURLWithPath: $0) }
        openRoot = openPath.map { URL(fileURLWithPath: $0) }
    }
}

private enum MarkdownHTMLRendererError: LocalizedError {
    case parserCreationFailed
    case documentCreationFailed
    case htmlRenderingFailed

    var errorDescription: String? {
        switch self {
        case .parserCreationFailed:
            return "Der Markdown-Parser konnte nicht initialisiert werden."
        case .documentCreationFailed:
            return "Das Markdown-Dokument konnte nicht geparst werden."
        case .htmlRenderingFailed:
            return "Das Markdown-Dokument konnte nicht in HTML gerendert werden."
        }
    }
}

private enum MarkdownHTMLRenderer {
    private static let options = CMARK_OPT_VALIDATE_UTF8 | CMARK_OPT_FOOTNOTES
    private static let extensionNames = [
        "table",
        "strikethrough",
        "autolink",
        "tagfilter",
        "tasklist"
    ]

    static func render(_ markdown: String) throws -> String {
        cmark_gfm_core_extensions_ensure_registered()

        guard let parser = cmark_parser_new(options) else {
            throw MarkdownHTMLRendererError.parserCreationFailed
        }
        defer { cmark_parser_free(parser) }

        attachExtensions(to: parser)

        let utf8Length = markdown.lengthOfBytes(using: .utf8)
        markdown.withCString { pointer in
            cmark_parser_feed(parser, pointer, utf8Length)
        }

        guard let document = cmark_parser_finish(parser) else {
            throw MarkdownHTMLRendererError.documentCreationFailed
        }
        defer { cmark_node_free(document) }

        guard let htmlPointer = cmark_render_html(document, options, cmark_parser_get_syntax_extensions(parser)) else {
            throw MarkdownHTMLRendererError.htmlRenderingFailed
        }
        defer { free(htmlPointer) }

        return String(cString: htmlPointer)
    }

    private static func attachExtensions(to parser: UnsafeMutablePointer<cmark_parser>) {
        for extensionName in extensionNames {
            extensionName.withCString { namePointer in
                if let syntaxExtension = cmark_find_syntax_extension(namePointer) {
                    cmark_parser_attach_syntax_extension(parser, syntaxExtension)
                }
            }
        }
    }
}

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

    private let fileManager = FileManager.default
    private let persistenceURL: URL
    private let launchConfiguration: LaunchConfiguration
    private var contentSignature: String = ""
    private var monitorTask: Task<Void, Never>?
    private var outlineNavigationRevision: Int = 0

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

    func openSources() {
        if let openRoot = launchConfiguration.openRoot {
            mergeSources(Self.makeSources(from: [openRoot]))
            return
        }

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.markdownDocument, .plainText]
        panel.prompt = "Öffnen"

        guard panel.runModal() == .OK else { return }
        mergeSources(Self.makeSources(from: panel.urls))
    }

    func removeSource(_ source: SourceRecord) {
        sources.removeAll { $0.id == source.id }
        Task { await refreshLibrary(preferredPath: activeDocument?.path) }
    }

    func selectLibraryItem(id: String?) {
        selectedLibraryItemID = id
        guard let id, let document = documents.first(where: { $0.id == id }) else { return }
        selectDocument(document, updateSelection: false)
    }

    func selectDocument(_ document: MarkdownDocumentRecord) {
        selectDocument(document, updateSelection: true)
    }

    func adjustZoom(by delta: Double) {
        zoomLevel = min(1.5, max(0.85, (zoomLevel + delta).rounded(toPlaces: 2)))
        persistState()
    }

    func resetZoom() {
        zoomLevel = 1.0
        persistState()
    }

    func refreshNow() {
        Task { await refreshLibrary(preferredPath: activeDocument?.path) }
    }

    func selectOutlineItem(id: String?) {
        selectedOutlineItemID = id
        guard let id, let item = outline.first(where: { $0.id == id }) else { return }
        navigateToOutline(item, updateSelection: false)
    }

    func navigateToOutline(_ item: OutlineItem) {
        navigateToOutline(item, updateSelection: true)
    }

    func revealCurrentDocument() {
        guard let activeDocument else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: activeDocument.path)])
    }

    func revealSource(_ source: SourceRecord) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: source.path)])
    }

    func revealDocument(_ document: MarkdownDocumentRecord) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: document.path)])
    }

    func setSidebarVisible(_ isVisible: Bool) {
        sidebarVisible = isVisible
        persistState()
    }

    func setInspectorVisible(_ isVisible: Bool) {
        inspectorVisible = isVisible
        persistState()
    }

    private func selectDocument(_ document: MarkdownDocumentRecord, updateSelection: Bool) {
        activeDocument = document
        if updateSelection {
            selectedLibraryItemID = document.id
        }
        loadDocument(at: document.path)
        persistState()
    }

    private func navigateToOutline(_ item: OutlineItem, updateSelection: Bool) {
        if updateSelection {
            selectedOutlineItemID = item.id
        }
        outlineNavigationRevision &+= 1
        outlineNavigationRequest = OutlineNavigationRequest(id: item.id, revision: outlineNavigationRevision)
    }

    private func mergeSources(_ newSources: [SourceRecord]) {
        guard !newSources.isEmpty else { return }

        var merged = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        for source in newSources {
            merged[source.id] = source
        }

        sources = merged.values.sorted { lhs, rhs in
            lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }

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
        zoomLevel = min(1.5, max(0.85, state.zoomLevel))
        sidebarVisible = state.sidebarVisible
        inspectorVisible = state.inspectorVisible

        Task {
            await refreshLibrary(preferredPath: state.activeDocumentPath)
        }
    }

    private func persistState() {
        guard !launchConfiguration.isUITesting else { return }

        let state = PersistedState(
            sources: sources,
            activeDocumentPath: activeDocument?.path,
            zoomLevel: zoomLevel,
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

        return urls.sorted { lhs, rhs in
            lhs.path.localizedCaseInsensitiveCompare(rhs.path) == .orderedAscending
        }
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
        } else if let firstDocument = nextDocuments.first {
            selectDocument(firstDocument)
        } else {
            activeDocument = nil
            selectedLibraryItemID = nil
            outline = []
            selectedOutlineItemID = nil
            renderedHTML = nil
            errorMessage = nil
            outlineNavigationRequest = nil
            persistState()
        }
    }

    private func loadDocument(at path: String) {
        let url = URL(fileURLWithPath: path)

        do {
            let markdown = try String(contentsOf: url, encoding: .utf8)
            let html = try MarkdownHTMLRenderer.render(markdown)
            renderedHTML = html
            outline = MarkdownOutlineParser.outline(from: html)
            selectedOutlineItemID = nil
            errorMessage = nil
            outlineNavigationRequest = nil
        } catch {
            renderedHTML = nil
            outline = []
            selectedOutlineItemID = nil
            errorMessage = error.localizedDescription
            outlineNavigationRequest = nil
        }
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

        return gatheredDocuments.sorted { lhs, rhs in
            if lhs.sourceLabel != rhs.sourceLabel {
                return lhs.sourceLabel.localizedCaseInsensitiveCompare(rhs.sourceLabel) == .orderedAscending
            }

            return lhs.relativePath.localizedCaseInsensitiveCompare(rhs.relativePath) == .orderedAscending
        }
    }

    nonisolated static func makeLibraryItems(
        from sources: [SourceRecord],
        documents: [MarkdownDocumentRecord]
    ) -> [LibraryItem] {
        let documentsBySource = Dictionary(grouping: documents, by: \.sourceID)

        return sources.map { source in
            switch source.kind {
            case .file:
                let document = documentsBySource[source.id]?.first
                return LibraryItem(
                    id: document?.id ?? source.id,
                    name: source.label,
                    symbolName: "doc.text",
                    kind: .sourceDocument(source, document),
                    children: []
                )
            case .folder:
                var builder = LibraryFolderBuilder()
                for document in documentsBySource[source.id] ?? [] {
                    builder.insert(document)
                }

                return LibraryItem(
                    id: source.id,
                    name: source.label,
                    symbolName: "folder.fill",
                    kind: .sourceFolder(source),
                    children: builder.makeItems(sourceID: source.id)
                )
            }
        }
    }

    nonisolated static func makeDocument(for url: URL, source: SourceRecord, rootURL: URL) -> MarkdownDocumentRecord {
        let relativePath = url.path.replacingOccurrences(of: rootURL.path + "/", with: "")

        let contextPath: String
        if source.kind == .file {
            contextPath = source.label
        } else {
            let relativeDirectory = url.deletingLastPathComponent().path.replacingOccurrences(of: rootURL.path + "/", with: "")
            contextPath = relativeDirectory.isEmpty ? source.label : "\(source.label)/\(relativeDirectory)"
        }

        return MarkdownDocumentRecord(
            id: url.path,
            sourceID: source.id,
            sourceKind: source.kind,
            sourceLabel: source.label,
            path: url.path,
            directory: url.deletingLastPathComponent().path,
            name: url.lastPathComponent,
            relativePath: relativePath,
            contextPath: contextPath
        )
    }

    nonisolated static func makeSources(from urls: [URL]) -> [SourceRecord] {
        urls.compactMap { url in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                return nil
            }

            if isDirectory.boolValue {
                return SourceRecord(
                    id: "folder:\(url.path)",
                    kind: .folder,
                    label: url.lastPathComponent,
                    path: url.path
                )
            }

            guard isMarkdownURL(url) else { return nil }
            return SourceRecord(
                id: "file:\(url.path)",
                kind: .file,
                label: url.lastPathComponent,
                path: url.path
            )
        }
    }

    nonisolated static func isMarkdownURL(_ url: URL) -> Bool {
        ["md", "markdown", "mdown", "mkd", "mkdn"].contains(url.pathExtension.lowercased())
    }
}

private struct LibraryFolderBuilder {
    private var folders: [String: LibraryFolderBuilder] = [:]
    private var files: [MarkdownDocumentRecord] = []

    mutating func insert(_ document: MarkdownDocumentRecord) {
        let components = document.relativePath
            .split(separator: "/")
            .map(String.init)

        guard !components.isEmpty else { return }
        insert(document, components: ArraySlice(components))
    }

    func makeItems(sourceID: String, relativePath: String = "") -> [LibraryItem] {
        let folderItems = folders.keys
            .sorted { lhs, rhs in
                lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
            .compactMap { name -> LibraryItem? in
                guard let child = folders[name] else { return nil }
                let childRelativePath = relativePath.isEmpty ? name : "\(relativePath)/\(name)"

                return LibraryItem(
                    id: "folder:\(sourceID):\(childRelativePath)",
                    name: name,
                    symbolName: "folder",
                    kind: .folder(sourceID: sourceID, relativePath: childRelativePath),
                    children: child.makeItems(sourceID: sourceID, relativePath: childRelativePath)
                )
            }

        let fileItems = files
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .map { document in
                LibraryItem(
                    id: document.id,
                    name: document.name,
                    symbolName: "doc.text",
                    kind: .document(document),
                    children: []
                )
            }

        return folderItems + fileItems
    }

    private mutating func insert(_ document: MarkdownDocumentRecord, components: ArraySlice<String>) {
        guard let firstComponent = components.first else { return }

        if components.count == 1 {
            files.append(document)
            return
        }

        var childFolder = folders[firstComponent, default: LibraryFolderBuilder()]
        childFolder.insert(document, components: components.dropFirst())
        folders[firstComponent] = childFolder
    }
}

enum MarkdownOutlineParser {
    static func outline(from renderedHTML: String) -> [OutlineItem] {
        guard
            let expression = try? NSRegularExpression(
                pattern: #"<h([1-6])(?:\s[^>]*)?>(.*?)</h\1>"#,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            )
        else {
            return []
        }

        let fullRange = NSRange(renderedHTML.startIndex..<renderedHTML.endIndex, in: renderedHTML)
        let matches = expression.matches(in: renderedHTML, options: [], range: fullRange)
        var slugCounts: [String: Int] = [:]

        return matches.compactMap { match in
            guard
                let levelRange = Range(match.range(at: 1), in: renderedHTML),
                let contentRange = Range(match.range(at: 2), in: renderedHTML),
                let level = Int(renderedHTML[levelRange])
            else {
                return nil
            }

            let title = plainText(fromHTMLFragment: String(renderedHTML[contentRange]))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let baseSlug = title.kebabCased().isEmpty ? "section" : title.kebabCased()
            let count = slugCounts[baseSlug, default: 0] + 1
            slugCounts[baseSlug] = count
            let id = count == 1 ? baseSlug : "\(baseSlug)-\(count)"

            return OutlineItem(id: id, title: title.isEmpty ? "Abschnitt" : title, level: level)
        }
    }

    private static func plainText(fromHTMLFragment fragment: String) -> String {
        let wrappedFragment = "<span>\(fragment)</span>"
        guard let data = wrappedFragment.data(using: .utf8) else {
            return fragment.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        }

        if let attributed = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ) {
            return attributed.string
        }

        return fragment.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
    }
}

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

extension String {
    func kebabCased() -> String {
        self.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { $0.lowercased() }
            .joined(separator: "-")
    }
}

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var columnVisibility: NavigationSplitViewVisibility

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        _columnVisibility = State(initialValue: viewModel.sidebarVisible ? .all : .detailOnly)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 360)
        } detail: {
            DocumentDetailView(viewModel: viewModel)
        }
        .inspector(isPresented: Binding(
            get: { viewModel.inspectorVisible && !viewModel.outline.isEmpty },
            set: { viewModel.setInspectorVisible($0) }
        )) {
            OutlineView(viewModel: viewModel)
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 340)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    viewModel.openSources()
                } label: {
                    Label("Öffnen", systemImage: "folder.badge.plus")
                        .labelStyle(.iconOnly)
                }
                .help("Ordner oder Markdown-Dateien öffnen")
                .accessibilityIdentifier("toolbar.open")

                Button {
                    viewModel.refreshNow()
                } label: {
                    Label("Neu laden", systemImage: viewModel.isRefreshing ? "arrow.clockwise.circle.fill" : "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .help("Bibliothek neu laden")
                .accessibilityIdentifier("toolbar.reload")
                .disabled(viewModel.sources.isEmpty)

                if viewModel.activeDocument != nil {
                    Button {
                        viewModel.revealCurrentDocument()
                    } label: {
                        Label("Im Finder zeigen", systemImage: "folder")
                            .labelStyle(.iconOnly)
                    }
                    .help("Aktuelles Dokument im Finder zeigen")
                    .accessibilityIdentifier("toolbar.reveal")
                }

                if !viewModel.outline.isEmpty {
                    Button {
                        viewModel.setInspectorVisible(!viewModel.inspectorVisible)
                    } label: {
                        Label(
                            viewModel.inspectorVisible ? "Navigation ausblenden" : "Navigation einblenden",
                            systemImage: "sidebar.right"
                        )
                        .labelStyle(.iconOnly)
                    }
                    .help(viewModel.inspectorVisible ? "Navigation ausblenden" : "Navigation einblenden")
                    .accessibilityIdentifier("toolbar.inspector")
                }

                ControlGroup {
                    Button {
                        viewModel.adjustZoom(by: -0.1)
                    } label: {
                        Label("Verkleinern", systemImage: "minus.magnifyingglass")
                            .labelStyle(.iconOnly)
                    }
                    .help("Verkleinern")
                    .accessibilityIdentifier("toolbar.zoomOut")

                    Button {
                        viewModel.resetZoom()
                    } label: {
                        Label("Tatsächliche Größe", systemImage: "textformat.size")
                            .labelStyle(.iconOnly)
                    }
                    .help("Tatsächliche Größe")
                    .accessibilityIdentifier("toolbar.actualSize")

                    Button {
                        viewModel.adjustZoom(by: 0.1)
                    } label: {
                        Label("Vergrößern", systemImage: "plus.magnifyingglass")
                            .labelStyle(.iconOnly)
                    }
                    .help("Vergrößern")
                    .accessibilityIdentifier("toolbar.zoomIn")
                }
            }
        }
        .frame(minWidth: 960, minHeight: 640)
        .navigationTitle(viewModel.navigationTitle)
        .onChange(of: columnVisibility) { _, newValue in
            viewModel.setSidebarVisible(newValue != .detailOnly)
        }
    }
}

struct SidebarView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Group {
            if viewModel.libraryItems.isEmpty {
                VStack(spacing: 16) {
                    ContentUnavailableView(
                        "Bibliothek starten",
                        systemImage: "books.vertical",
                        description: Text("Öffne einen Ordner oder einzelne Markdown-Dateien.")
                    )

                    Button("Öffnen…") {
                        viewModel.openSources()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("empty.open")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(
                    viewModel.libraryItems,
                    children: \.childItems,
                    selection: Binding(
                        get: { viewModel.selectedLibraryItemID },
                        set: { viewModel.selectLibraryItem(id: $0) }
                    )
                ) { item in
                    LibraryRow(item: item)
                        .tag(item.id)
                        .contextMenu {
                            if let source = item.source {
                                Button("Im Finder zeigen", systemImage: "folder") {
                                    viewModel.revealSource(source)
                                }
                                Divider()
                                Button("Quelle entfernen", systemImage: "trash", role: .destructive) {
                                    viewModel.removeSource(source)
                                }
                            } else if let document = item.document {
                                Button("Im Finder zeigen", systemImage: "folder") {
                                    viewModel.revealDocument(document)
                                }
                            }
                        }
                        .help(item.helpText ?? item.name)
                }
                .listStyle(.sidebar)
                .accessibilityIdentifier("sidebar.library")
            }
        }
        .navigationTitle("Bibliothek")
    }
}

private struct LibraryRow: View {
    let item: LibraryItem

    var body: some View {
        Label(item.name, systemImage: item.symbolName)
            .lineLimit(1)
    }
}

struct DocumentDetailView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let document = viewModel.activeDocument {
                if let errorMessage = viewModel.errorMessage {
                    ContentUnavailableView(
                        "Datei konnte nicht geladen werden",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else if let renderedHTML = viewModel.renderedHTML {
                    MarkdownWebPreview(
                        html: renderedHTML,
                        baseURL: URL(fileURLWithPath: document.directory, isDirectory: true),
                        zoomLevel: viewModel.zoomLevel,
                        colorScheme: colorScheme,
                        navigationRequest: viewModel.outlineNavigationRequest
                    )
                    .accessibilityIdentifier("detail.preview")
                } else {
                    ContentUnavailableView(
                        "Keine Vorschau verfügbar",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("Der Markdown-Inhalt konnte nicht gerendert werden.")
                    )
                }
            } else {
                ContentUnavailableView(
                    "Keine Datei ausgewählt",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Öffne links einen Ordner oder einzelne Markdown-Dateien.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(viewModel.navigationTitle)
    }
}

struct OutlineView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        List(
            selection: Binding(
                get: { viewModel.selectedOutlineItemID },
                set: { viewModel.selectOutlineItem(id: $0) }
            )
        ) {
            ForEach(viewModel.outline) { item in
                Text(item.title)
                    .padding(.leading, CGFloat(max(0, item.level - 1) * 14))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .tag(item.id)
                    .onTapGesture {
                        viewModel.navigateToOutline(item)
                    }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Navigation")
        .accessibilityIdentifier("inspector.outline")
    }
}

private enum PreviewMetrics {
    static let idealWidth: Int = 920
    static let minimumWidth: Int = 560
    static let horizontalPadding: Int = 32
    static let verticalPadding: Int = 28
    static let bottomPadding: Int = 88
}

private struct HTMLPreviewPalette {
    let text: String
    let secondaryText: String
    let divider: String
    let link: String
    let codeBackground: String
    let blockquoteBorder: String

    init(colorScheme: ColorScheme) {
        switch colorScheme {
        case .dark:
            text = "#f4f4f5"
            secondaryText = "#9b9da4"
            divider = "#3a3c43"
            link = "#5da0ff"
            codeBackground = "#23252b"
            blockquoteBorder = "#4a4d57"
        default:
            text = "#111214"
            secondaryText = "#666a73"
            divider = "#d9dbe0"
            link = "#0b57d0"
            codeBackground = "#f4f5f7"
            blockquoteBorder = "#d5d8de"
        }
    }
}

private enum HTMLPreviewRenderer {
    static func document(for bodyHTML: String, colorScheme: ColorScheme) -> String {
        let palette = HTMLPreviewPalette(colorScheme: colorScheme)

        return #"""
        <!DOCTYPE html>
        <html lang="de">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            :root {
              color-scheme: \#(colorScheme == .dark ? "dark" : "light");
            }

            * {
              box-sizing: border-box;
            }

            html,
            body {
              margin: 0;
              min-height: 100%;
              background: transparent;
              color: \#(palette.text);
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
              font-size: 16px;
              line-height: 1.6;
            }

            main {
              width: min(\#(PreviewMetrics.idealWidth)px, max(\#(PreviewMetrics.minimumWidth)px, calc(100vw - \#(PreviewMetrics.horizontalPadding * 2)px)));
              margin: 0 auto;
              padding: \#(PreviewMetrics.verticalPadding)px \#(PreviewMetrics.horizontalPadding)px \#(PreviewMetrics.bottomPadding)px;
            }

            h1,
            h2,
            h3,
            h4,
            h5,
            h6 {
              color: \#(palette.text);
              line-height: 1.25;
              scroll-margin-top: 20px;
            }

            h1 {
              margin: 0 0 18px;
              font-size: 2em;
            }

            h2 {
              margin: 28px 0 18px;
              font-size: 1.5em;
              padding-bottom: 0.25em;
              border-bottom: 1px solid \#(palette.divider);
            }

            h3 {
              margin: 28px 0 16px;
              font-size: 1.25em;
            }

            h4,
            h5,
            h6 {
              margin: 24px 0 16px;
            }

            p,
            ul,
            ol,
            blockquote,
            pre,
            table {
              margin: 0 0 16px;
            }

            ul,
            ol {
              padding-left: 1.4em;
            }

            li + li {
              margin-top: 0.35em;
            }

            a {
              color: \#(palette.link);
            }

            code {
              font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
              font-size: 0.85em;
              padding: 0.15em 0.35em;
              border-radius: 6px;
              background: \#(palette.codeBackground);
            }

            pre {
              overflow-x: auto;
              padding: 16px;
              border-radius: 10px;
              background: \#(palette.codeBackground);
            }

            pre code {
              padding: 0;
              background: transparent;
            }

            blockquote {
              margin-left: 0;
              padding-left: 16px;
              border-left: 4px solid \#(palette.blockquoteBorder);
              color: \#(palette.secondaryText);
            }

            img {
              max-width: 100%;
              height: auto;
            }

            table {
              border-collapse: collapse;
              width: max-content;
              max-width: 100%;
            }

            th,
            td {
              padding: 6px 13px;
              border: 1px solid \#(palette.divider);
              vertical-align: top;
            }

            th {
              font-weight: 600;
            }

            hr {
              margin: 24px 0;
              border: 0;
              border-top: 1px solid \#(palette.divider);
            }
          </style>
          <script>
            function markdownViewerSlugify(text) {
              const parts = (text || "")
                .toLocaleLowerCase()
                .split(/[^\p{L}\p{N}]+/u)
                .filter(Boolean);
              return parts.join("-") || "section";
            }

            document.addEventListener("DOMContentLoaded", () => {
              const counts = {};
              for (const heading of document.querySelectorAll("h1, h2, h3, h4, h5, h6")) {
                const base = markdownViewerSlugify(heading.textContent);
                counts[base] = (counts[base] || 0) + 1;
                heading.id = counts[base] === 1 ? base : `${base}-${counts[base]}`;
              }
            });
          </script>
        </head>
        <body>
          <main>\#(bodyHTML)</main>
        </body>
        </html>
        """#
    }
}

struct MarkdownWebPreview: NSViewRepresentable {
    let html: String
    let baseURL: URL
    let zoomLevel: Double
    let colorScheme: ColorScheme
    let navigationRequest: OutlineNavigationRequest?

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        var lastLoadedDocument: String?
        var lastNavigationRequest: OutlineNavigationRequest?

        func scrollToAnchor(_ id: String, animated: Bool) {
            let escapedID = id
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            let behavior = animated ? "smooth" : "instant"
            let script = """
            (function() {
              const target = document.getElementById('\(escapedID)');
              if (!target) { return false; }
              target.scrollIntoView({ behavior: '\(behavior)', block: 'start', inline: 'nearest' });
              return true;
            })();
            """
            webView?.evaluateJavaScript(script, completionHandler: nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let request = lastNavigationRequest {
                scrollToAnchor(request.id, animated: false)
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard
                navigationAction.navigationType == .linkActivated,
                let url = navigationAction.request.url,
                let scheme = url.scheme?.lowercased(),
                ["http", "https"].contains(scheme)
            else {
                decisionHandler(.allow)
                return
            }

            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.setAccessibilityIdentifier("detail.webPreview")
        context.coordinator.webView = webView
        update(webView: webView, coordinator: context.coordinator)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        update(webView: nsView, coordinator: context.coordinator)
    }

    private func update(webView: WKWebView, coordinator: Coordinator) {
        let fullDocument = HTMLPreviewRenderer.document(for: html, colorScheme: colorScheme)

        if coordinator.lastLoadedDocument != fullDocument {
            coordinator.lastLoadedDocument = fullDocument
            webView.loadHTMLString(fullDocument, baseURL: baseURL)
        }

        if abs(webView.pageZoom - zoomLevel) > 0.001 {
            webView.pageZoom = zoomLevel
        }

        if coordinator.lastNavigationRequest != navigationRequest {
            coordinator.lastNavigationRequest = navigationRequest
            if let navigationRequest {
                coordinator.scrollToAnchor(navigationRequest.id, animated: true)
            }
        }
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
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
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
