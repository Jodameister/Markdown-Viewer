import Foundation

struct LibraryFolderBuilder {
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
                    children: child.makeItems(
                        sourceID: sourceID,
                        relativePath: childRelativePath
                    )
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

    private mutating func insert(
        _ document: MarkdownDocumentRecord,
        components: ArraySlice<String>
    ) {
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
        guard let expression = headingExpression else {
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
            let baseSlug = makeBaseSlug(for: title)
            let count = slugCounts[baseSlug, default: 0] + 1
            slugCounts[baseSlug] = count
            let id = count == 1 ? baseSlug : "\(baseSlug)-\(count)"
            let fallbackTitle = title.isEmpty ? "Abschnitt" : title

            return OutlineItem(id: id, title: fallbackTitle, level: level)
        }
    }

    private static let headingExpression = try? NSRegularExpression(
        pattern: #"<h([1-6])(?:\s[^>]*)?>(.*?)</h\1>"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )

    private static func makeBaseSlug(for title: String) -> String {
        let slug = title.kebabCased()
        return slug.isEmpty ? "section" : slug
    }

    private static func plainText(fromHTMLFragment fragment: String) -> String {
        let wrappedFragment = "<span>\(fragment)</span>"
        guard let data = wrappedFragment.data(using: .utf8) else {
            return fragment.replacingOccurrences(
                of: #"<[^>]+>"#,
                with: "",
                options: .regularExpression
            )
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

        return fragment.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: "",
            options: .regularExpression
        )
    }
}
