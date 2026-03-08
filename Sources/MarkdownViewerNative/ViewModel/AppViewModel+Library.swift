import Foundation

extension AppViewModel {
    func refreshLibrary(preferredPath: String?) async {
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

    func loadDocument(at path: String) {
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
                let document = makeDocument(
                    for: url,
                    source: source,
                    rootURL: url.deletingLastPathComponent()
                )
                gatheredDocuments.append(document)
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
                    let document = makeDocument(for: url, source: source, rootURL: rootURL)
                    gatheredDocuments.append(document)
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

    nonisolated static func makeDocument(
        for url: URL,
        source: SourceRecord,
        rootURL: URL
    ) -> MarkdownDocumentRecord {
        let relativePath = url.path.replacingOccurrences(of: rootURL.path + "/", with: "")
        let contextPath = makeContextPath(for: url, source: source, rootURL: rootURL)

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

    nonisolated static func preferredDocumentPath(from urls: [URL]) -> String? {
        urls.first(where: isMarkdownURL(_:))?.path
    }

    nonisolated static func supportsSourceURL(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }

        return isDirectory.boolValue || isMarkdownURL(url)
    }

    nonisolated static func isMarkdownURL(_ url: URL) -> Bool {
        ["md", "markdown", "mdown", "mkd", "mkdn"].contains(url.pathExtension.lowercased())
    }

    private nonisolated static func makeContextPath(
        for url: URL,
        source: SourceRecord,
        rootURL: URL
    ) -> String {
        guard source.kind == .folder else {
            return source.label
        }

        let relativeDirectory = url.deletingLastPathComponent().path.replacingOccurrences(
            of: rootURL.path + "/",
            with: ""
        )

        if relativeDirectory.isEmpty {
            return source.label
        }

        return "\(source.label)/\(relativeDirectory)"
    }
}
