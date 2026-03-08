import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var columnVisibility: NavigationSplitViewVisibility

    private var reloadSymbolName: String {
        viewModel.isRefreshing ? "arrow.clockwise.circle.fill" : "arrow.clockwise"
    }

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
                    Label("Neu laden", systemImage: reloadSymbolName)
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
