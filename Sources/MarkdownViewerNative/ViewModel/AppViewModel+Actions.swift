import AppKit

extension AppViewModel {
    func openSources() {
        if let openRoot = launchConfiguration.openRoot {
            mergeSourceURLs([openRoot])
            return
        }

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.markdownDocument, .plainText]
        panel.prompt = "Öffnen"

        guard panel.runModal() == .OK else { return }
        mergeSourceURLs(panel.urls)
    }

    func openIncomingItems(_ urls: [URL]) {
        let supportedURLs = urls.filter(Self.supportsSourceURL(_:))
        guard !supportedURLs.isEmpty else { return }
        mergeSourceURLs(supportedURLs)
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

    private func mergeSourceURLs(_ urls: [URL]) {
        let newSources = Self.makeSources(from: urls)
        let preferredPath = Self.preferredDocumentPath(from: urls)
        mergeSources(newSources, preferredPath: preferredPath)
    }

    private func selectDocument(
        _ document: MarkdownDocumentRecord,
        updateSelection: Bool
    ) {
        activeDocument = document
        if updateSelection {
            selectedLibraryItemID = document.id
        }
        loadDocument(at: document.path)
        persistState()
    }

    private func navigateToOutline(
        _ item: OutlineItem,
        updateSelection: Bool
    ) {
        if updateSelection {
            selectedOutlineItemID = item.id
        }
        outlineNavigationRevision &+= 1
        outlineNavigationRequest = OutlineNavigationRequest(
            id: item.id,
            revision: outlineNavigationRevision
        )
    }

    private func mergeSources(
        _ newSources: [SourceRecord],
        preferredPath: String? = nil
    ) {
        guard !newSources.isEmpty else { return }

        var merged = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        for source in newSources {
            merged[source.id] = source
        }

        sources = merged.values.sorted { lhs, rhs in
            lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }

        let nextPreferredPath = preferredPath ?? activeDocument?.path
        Task { await refreshLibrary(preferredPath: nextPreferredPath) }
    }
}
