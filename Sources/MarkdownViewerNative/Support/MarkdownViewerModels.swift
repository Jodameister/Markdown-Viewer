import Foundation
import UniformTypeIdentifiers

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

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

extension String {
    func kebabCased() -> String {
        components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { $0.lowercased() }
            .joined(separator: "-")
    }
}
