# Interaction checks

## 0.24.0 follow-up

Verified the shared workspace header in the installed `/Applications/FontShelf.app` 0.24.0 (32): Ff, FontShelf, the Library/Spaces switcher and collapse control occupy the same layout in Library and Spaces. Hiding the sidebar from either workspace removed its complete 256-point footprint and expanded the active content to the left edge; the small accessible **Show sidebar** control restored it without covering the workspace controls.

The View menu changed between **Hide Sidebar** and **Show Sidebar** with the current state, and Control-Command-S toggled it. Collapsing in Library and opening Spaces through the File menu retained the collapsed state. After a real quit and relaunch, FontShelf reopened with the sidebar still collapsed; the sidebar was restored at the end of QA. The installed app's plist reports 0.24.0 build 32, its code signature verifies, and its executable matches the verified build byte-for-byte.

Font kerning now has one visible control. Legacy boards that stored `kern` in generic OpenType settings continue to render the same way, while the checkbox, Figma payload, developer handoff and web-font audit all use one effective value. Automated checks cover legacy off/on, explicit conflicts, toggle cleanup, JSON round-trip, Figma canonicalization and CSS output. The final installed performance audit measured a 3,301 ms full scan of 4,252 styles, a 5.87 ms filter pass, and 1.86 ms uncached versus 0.000350 ms cached canvas planning.

## 0.20.0 follow-up

Verified **Tools → Font Health** opens as a first-class Library tool with Scan Library, Inspect file, user-font and clean-file filters, searchable results, an identity summary, severity-specific findings, proposed-fix checkboxes, Finder reveal, repaired-copy export and guarded original-repair controls. The same tool is reachable from the File menu and each family's actions.

The first broad live scan exposed modern Apple/Adobe naming conventions as potential false positives. RIBBI and version-string normalization were consequently downgraded to optional compatibility notes, which do not place a font in the default needs-review list or start selected. The user-font scope was narrowed to `~/Library/Fonts`, `/Library/Fonts` and the user's explicit watched folders instead of application/SDK bundles. The refined live scan inspected 2,624 accessible user/watched files and reduced the default review list to six actual warning/error cases; a legacy Fontographer file correctly surfaced three empty name records and an incorrect glyph-table checksum. No font repair or file write was performed during live checking.

Automated checks build a deliberately malformed legacy TrueType fixture with an empty trademark, duplicate full name, non-RIBBI legacy subfamily and nonstandard version record. They verify the proposed fixes, rebuilt name table, preserved typographic identity, resolved findings and the required whole-file checksum. The test suite also rebuilds a real local font in memory and requires Core Text to accept it. Repaired-copy output is always passed to Core Text before writing; in-place repair makes a sibling backup and requires explicit confirmation.

## 0.19.0 follow-up

Verified that selecting Canvas 1, Canvas 2 and Canvas 3 preserves all three in the visible comparison; hiding an inactive canvas removes only that canvas, and **Only this** returns to the active canvas in one action. The checkmarked **Shown** menu provides the same explicit controls plus Show every canvas, while Quick A/B remains a separate same-format, same-width switching mode.

The canvas toolbar now exposes the actual font count for the active composition. Its summary was checked at all three detail levels: unique font names, font-to-role mapping, and full size/line-height/tracking/axis/feature settings. Copy, plain-text export and Markdown export share the same visible-text-only model; automated checks cover Markdown escaping for designer-controlled names.

The same summary exposes **Create collection** for canvas, typeboard and project scopes; the typeboard and project action menus expose their matching scopes directly. Collection creation resolves used PostScript styles back to Library families, deduplicates multiple styles of one family, rejects unavailable-only scopes and existing names, persists immediately, and becomes available to Library and typeboard font filters. The scope, mapping and no-overwrite behaviors are regression-tested; the live naming sheet was opened and cancelled to avoid altering the user's collections.

Type-role buttons report their number of visible uses. Clicking a used role locates its first matching canvas element and exposes the exact selected text; drag payloads add another instance at the indicated canvas insertion point with the role's saved sample and shared typography. Automated checks cover insertion order, style/sample preservation, cross-canvas payload rejection and read-only comparison rejection. A physical automated SwiftUI-to-AppKit role drag could not be triggered reliably, so that gesture still merits hands-on trackpad testing.

Website and poster formats were inspected live as distinct compositions rather than simple size variants. Layout validation covers those plus product UI and editorial at 390, 768, 960 and 1200 points; the regression suite also requires unique section signatures across every designed format.

## 0.18.0 follow-up

Verified the developer handoff exports every canvas into a local package with production CSS, variable axes and OpenType features, Tailwind v3/v4 configuration, versioned JSON tokens, preload examples, SwiftUI and Android Compose starter definitions, exact source-board data, and a standalone printable HTML specimen. The generated Swift file type-checks and the Tailwind configuration parses with every exported style. Font files are never copied; the manifest calls out licensing and required assets, while the specimen can use an already-installed local font for review.

Project, typeboard, and collection names now edit directly in place without pencil buttons. Clicking a selected name enters editing immediately with the current name selected; Return saves and Escape cancels. An unselected sidebar name selects on first click and edits on double-click. Live checks covered sidebar and header editing, keyboard focus, saving, project synchronization, and duplicate collection-name protection. The empty QA collection created for these checks was removed afterward; the user's existing collection and projects were not changed.

## 0.17.0 follow-up

Also verified the Add & Watch picker explains recursive updates, choosing a temporary empty folder opens Watched folders automatically, and the new entry has activation off by default. Stopped watching only that temporary test folder afterward; the user's three existing watches were left unchanged. Verified 200% canvas zoom through the menu and return to Fit. Library scanning can queue newly chosen folders instead of disabling the picker.

Live-checked visible canvas tabs and Show all canvases on a two-canvas board; exact canvas button-label selection into the UI label editor; editing that label without changing the headline, followed by Undo; the existing Portfolio Site collection filtering the font chooser to 14 styles; and the persistent trash action opening confirmation for an unselected board (cancelled without deleting it). The Library live-folders shortcut is visible. Regression checks cover collection/category intersection, manual category overrides, favorites, exact role hit-testing, selected-text serialization/rendering, legacy naming and zoom bounds.

Pinch and Command-scroll handlers are implemented with viewport-limited native event monitoring. Physical trackpad gesture feel has not been verified by automation. Native `.fig` decoding remains unimplemented: Figma's [local-copy guide](https://help.figma.com/hc/en-us/articles/8403626871063-Save-a-local-copy-of-files) and [import guide](https://help.figma.com/hc/en-us/articles/360041003114-Import-files-to-the-file-browser) describe reopening the file in Figma; no supported local decoding contract was found during this pass. The in-app import menu explains the bridge workflow.

Tested on macOS 26.3, Apple Silicon, September 16, 2026. These checks cover the exercised paths, not every font, Figma document or accessibility configuration.

## Live checks

- Exported two FontShelf directions through the bundled development plugin into editable Figma frames. Inspected the headline's actual font, size, line height and fill in Figma, edited its size and restored it.
- Exported a selected Figma frame to JSON through the live plugin, saved it and imported it through FontShelf's file picker. Verified the original layout, text layers, Georgia headline and Helvetica body styles.
- Edited the imported headline to “From Figma, now editable.” directly in FontShelf. Dragged it on the canvas and verified Undo returned it to its original position.
- Deleted the imported test typeboard using its sidebar trash action and confirmation. Verified Cmd-Z restored the board, selection and edited text.
- Verified the space title no longer clips and Export/overflow controls no longer touch at both tested wide and narrower desktop widths. The enlarged font chooser remains opaque over the canvas and focuses search on opening.
- Verified native canvas section reordering, insertion at beginning/end, Undo/Redo, section removal/restoration, font searching, empty search results, font selection and font Undo.
- Verified the inspector divider width persists after relaunch.
- Verified imported text edits survive relaunch, native Arrangement-list drag ordering and Undo, Quick A/B selection and Cmd-backslash switching, and full numeric size-edit Undo/Redo after correcting native field-editor routing.

## Automated checks

- Swift regression suite: imported geometry/style persistence, legacy decoding, validation, typeboard deletion/restore, Undo coalescing, canvas layouts, fonts, tags, watched-folder protection and exports.
- Node plugin suite: Figma API mock covering editable text, shared metadata without an assigned plugin ID, missing fonts, rollback, reverse frame export, coordinate conversion and unsupported-vector warnings. This is separate from the live editor checks above.

## Design guidance

Applied Apple's guidance on [toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars), [Undo and Redo](https://developer.apple.com/design/human-interface-guidelines/undo-and-redo), and [drag and drop](https://developer.apple.com/design/human-interface-guidelines/drag-and-drop): group related actions, expose recoverable editing, label Undo actions, and give insertion feedback.

## Boundaries

The Figma bridge uses selected-frame JSON, not `.fig` decoding or live sync. Unsupported visual features are reported; this is not a full-fidelity Figma renderer. Full VoiceOver and every window-size/font combination have not been audited. App Store sandbox activation verification remains outstanding.
