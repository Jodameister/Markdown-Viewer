# Apple HIG Audit

Stand: 7. Maerz 2026

Die App wurde gegen die aktuelle Apple-Dokumentation aus `apple-doc-mcp` und die offiziellen Human Interface Guidelines fuer macOS abgeglichen. Ziel dieses Dokuments ist eine explizite Pass/Fail-Liste statt einer rein subjektiven Einschaetzung.

| Quelle | Anforderung | Umsetzung im Projekt | Status |
| --- | --- | --- | --- |
| [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos) | Primäre Navigation in nativen Seitenleisten und Split Views fuehren. | Die App nutzt `NavigationSplitView` fuer Bibliothek und Detailbereich. | pass |
| [List](https://developer.apple.com/documentation/swiftui/list) | Hierarchische Inhalte mit nativer Auswahl statt eigener Selektionsoptik darstellen. | Die linke Bibliothek nutzt `List(...children:selection:)`; manuelle Sidebar-Selection-Fills wurden entfernt. | pass |
| [InspectorCommands](https://developer.apple.com/documentation/swiftui/inspectorcommands) | Ergaenzende Inhalte in einem Inspector und ueber Standard-Commands steuerbar machen. | Die rechte Outline bleibt ein `.inspector`; `InspectorCommands()` ist eingebunden. | pass |
| [SidebarCommands](https://developer.apple.com/documentation/swiftui/sidebarcommands) | Sidebar ueber System-Commands und den Standard-Toolbar-Toggle steuerbar machen. | Der Default-Sidebar-Toggle bleibt aktiv; `SidebarCommands()` ist eingebunden. | pass |
| [ToolbarCommands](https://developer.apple.com/documentation/swiftui/toolbarcommands) | Toolbar an die nativen Fenster- und Toolbar-Konventionen anbinden. | `ToolbarCommands()` ist eingebunden; globale In-Content-Buttons wurden entfernt. | pass |
| [Commands](https://developer.apple.com/documentation/swiftui/commands) | Dokument- und Bibliotheksaktionen in Menues und Shortcuts exposeen. | Es gibt `Commands` fuer Oeffnen, Neu laden, Im Finder zeigen und Zoom. | pass |
| [CommandMenu](https://developer.apple.com/documentation/swiftui/commandmenu) | App-spezifische Befehle in einem eigenen Top-Level-Menue gruppieren. | Die App fuehrt ein `Dokument`-Menue fuer dokumentbezogene Aktionen. | pass |
| [toolbar(removing:)](https://developer.apple.com/documentation/swiftui/view/toolbar(removing:)) | Default-Toolbar-Items nur dann entfernen, wenn es funktional notwendig ist. | Der Standard-Sidebar-Toggle wird nicht mehr entfernt. | pass |
| [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/) | Systemdarstellung respektieren, keine eigene Theme-Umschaltung in der Hauptoberflaeche erzwingen. | Die manuelle Light/Dark/System-Umschaltung wurde entfernt; die App folgt dem System. | pass |
| [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos) | Globales Fenster-Chrome nicht im Dokumentinhalt nachbauen. | Der fruehere Detail-Header und die schwebende Aktionsleiste wurden entfernt. | pass |
| [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos) | Toolbar auf wenige primaere Aktionen begrenzen. | Toolbar enthaelt Oeffnen, Neu laden, Im Finder zeigen, Inspector und Zoom. | pass |
| [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/) | Offizielle Apple-Symbole mit klarer Semantik verwenden. | Aktionen nutzen `folder.badge.plus`, `arrow.clockwise`, `folder`, `sidebar.right`, `minus.magnifyingglass`, `plus.magnifyingglass`, `doc.text`, `folder.fill`. | pass |
| [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/) | Interfaces mit Tastatur und Accessibility-Hinweisen bedienbar halten. | Toolbar-Controls haben Labels/Help; Sidebar, Inspector und Preview sind fuer UI-Tests und Accessibility identifizierbar. | pass |
| [GlassButtonStyle](https://developer.apple.com/documentation/swiftui/glassbuttonstyle) | Glass-Effekte ueber Standardkomponenten statt eigene Kapsel-Chrome nutzen. | Es gibt keine custom Glass-Overlays mehr; das Fenster nutzt das native macOS-Chrome. | pass |
| [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos) | Seitenleisten und Inspector sollen vom Nutzer ein- und ausblendbar sowie in der Breite anpassbar sein. | Sidebar und Inspector sind systemsteuerbar und benutzerresizable. | pass |
| [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/) | Fenster muessen auf sinnvolle Mindestgroessen reagieren. | Mindestgroesse wurde auf `960x640` reduziert. | pass |

## Laufzeit-Checkliste

- Hellmodus und Dunkelmodus pruefen.
- `Reduce Transparency` pruefen.
- Vollbild und schmale Fensterbreiten pruefen.
- Sidebar mit `Option-Command-S` ein- und ausblenden.
- Inspector ueber Toolbar und View-Menue ein- und ausblenden.
- Zoom ueber `Command-=`, `Command--` und `Command-0` pruefen.
- Outline-Klicks gegen Anker-Navigation im Preview pruefen.
