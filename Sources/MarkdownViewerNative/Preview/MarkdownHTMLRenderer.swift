import cmark_gfm
import cmark_gfm_extensions
import Foundation

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

enum MarkdownHTMLRenderer {
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

        let syntaxExtensions = cmark_parser_get_syntax_extensions(parser)
        guard let htmlPointer = cmark_render_html(document, options, syntaxExtensions) else {
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
