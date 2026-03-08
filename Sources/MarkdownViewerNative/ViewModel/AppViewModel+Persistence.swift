import Foundation

extension AppViewModel {
    func restoreState() {
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

    func persistState() {
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

    func startMonitoring() {
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

    func computeSignature() -> String {
        let parts = sources.flatMap { source -> [String] in
            if source.kind == .file {
                let url = URL(fileURLWithPath: source.path)
                return ["\(source.path)#\(modificationTimestamp(for: url))"]
            }

            let rootURL = URL(fileURLWithPath: source.path)
            return enumerateMarkdownURLs(at: rootURL).map { url in
                "\(url.path)#\(modificationTimestamp(for: url))"
            }
        }

        return parts.sorted().joined(separator: "|")
    }

    func enumerateMarkdownURLs(at rootURL: URL) -> [URL] {
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

    private func modificationTimestamp(for url: URL) -> TimeInterval {
        let resourceValues = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return resourceValues?.contentModificationDate?.timeIntervalSince1970 ?? 0
    }
}
