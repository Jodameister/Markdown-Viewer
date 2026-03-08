import SwiftUI

enum PreviewMetrics {
    static let idealWidth: Int = 920
    static let minimumWidth: Int = 560
    static let horizontalPadding: Int = 32
    static let verticalPadding: Int = 28
    static let bottomPadding: Int = 88

    static var mainWidth: String {
        """
        min(\(idealWidth)px, max(\(minimumWidth)px, calc(100vw - \(horizontalPadding * 2)px)))
        """
    }

    static var mainPadding: String {
        "\(verticalPadding)px \(horizontalPadding)px \(bottomPadding)px"
    }
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

enum HTMLPreviewRenderer {
    static func document(for bodyHTML: String, colorScheme: ColorScheme) -> String {
        let palette = HTMLPreviewPalette(colorScheme: colorScheme)
        let styleSheet = css(for: palette, colorScheme: colorScheme)

        return """
        <!DOCTYPE html>
        <html lang="de">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
        \(styleSheet)
          </style>
          <script>
        \(headingScript)
          </script>
        </head>
        <body>
          <main>\(bodyHTML)</main>
        </body>
        </html>
        """
    }

    private static func css(for palette: HTMLPreviewPalette, colorScheme: ColorScheme) -> String {
        let colorSchemeName = colorScheme == .dark ? "dark" : "light"

        return [
            baseCSS(colorSchemeName: colorSchemeName, palette: palette),
            headingCSS(palette: palette),
            bodyCSS(palette: palette),
            tableCSS(palette: palette)
        ].joined(separator: "\n\n")
    }

    private static func baseCSS(
        colorSchemeName: String,
        palette: HTMLPreviewPalette
    ) -> String {
        """
        :root {
          color-scheme: \(colorSchemeName);
        }

        * {
          box-sizing: border-box;
        }

        html,
        body {
          margin: 0;
          min-height: 100%;
          background: transparent;
          color: \(palette.text);
          font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
          font-size: 16px;
          line-height: 1.6;
        }

        main {
          width: \(PreviewMetrics.mainWidth);
          margin: 0 auto;
          padding: \(PreviewMetrics.mainPadding);
        }
        """
    }

    private static func headingCSS(palette: HTMLPreviewPalette) -> String {
        """
        h1,
        h2,
        h3,
        h4,
        h5,
        h6 {
          color: \(palette.text);
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
          border-bottom: 1px solid \(palette.divider);
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
        """
    }

    private static func bodyCSS(palette: HTMLPreviewPalette) -> String {
        [
            textCSS(palette: palette),
            codeCSS(palette: palette),
            blockquoteCSS(palette: palette),
            mediaCSS()
        ].joined(separator: "\n\n")
    }

    private static func textCSS(palette: HTMLPreviewPalette) -> String {
        """
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
          color: \(palette.link);
        }
        """
    }

    private static func codeCSS(palette: HTMLPreviewPalette) -> String {
        """
        code {
          font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
          font-size: 0.85em;
          padding: 0.15em 0.35em;
          border-radius: 6px;
          background: \(palette.codeBackground);
        }

        pre {
          overflow-x: auto;
          padding: 16px;
          border-radius: 10px;
          background: \(palette.codeBackground);
        }

        pre code {
          padding: 0;
          background: transparent;
        }
        """
    }

    private static func blockquoteCSS(palette: HTMLPreviewPalette) -> String {
        """
        blockquote {
          margin-left: 0;
          padding-left: 16px;
          border-left: 4px solid \(palette.blockquoteBorder);
          color: \(palette.secondaryText);
        }
        """
    }

    private static func mediaCSS() -> String {
        """
        img {
          max-width: 100%;
          height: auto;
        }
        """
    }

    private static func tableCSS(palette: HTMLPreviewPalette) -> String {
        """
        table {
          border-collapse: collapse;
          width: max-content;
          max-width: 100%;
        }

        th,
        td {
          padding: 6px 13px;
          border: 1px solid \(palette.divider);
          vertical-align: top;
        }

        th {
          font-weight: 600;
        }

        hr {
          margin: 24px 0;
          border: 0;
          border-top: 1px solid \(palette.divider);
        }
        """
    }

    private static let headingScript = #"""
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
        """#
}
