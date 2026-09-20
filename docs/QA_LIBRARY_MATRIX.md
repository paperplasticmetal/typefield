# FontShelf Library / FontInspector / GlyphBrowser interaction matrix

Date: 2026-09-19. Build under test: `/tmp/fontshelf-interaction-qa/dist/FontShelf.app` (isolated QA copy and disposable app state). GUI evidence below is from the Luna runtime pass; “LIVE PASS” means the action was performed and the resulting accessibility state was inspected. No user font files were changed.

| Area | Interaction | Status | Evidence |
|---|---|---|---|
| Library | Open exact isolated app; Library selected | LIVE PASS | Window title FontShelf QA; Library radio selected; 778 families / 4,252 styles visible |
| Library | Search matching term `Helvetica` | LIVE PASS | 2 matching families, Helvetica and Helvetica Neue |
| Library | Search no-match and clear | LIVE PASS | `zzzz-no-font` shows “No matching fonts”; Clear filters restores 778 families |
| Library | Category filter Serif and return All Fonts | LIVE PASS | Serif shows 127 families; All Fonts restores full set |
| Library | List and Grid View toggles | LIVE PASS | List value 1 then Grid View value 1; grid cards expose family controls |
| Library | Favorite add/remove | LIVE PASS | First card star changes to star.fill; Favorites count 1; toggled back to 0 |
| Library | Shortlist add/remove | LIVE PASS | First card changes to Selected/checkmark.square.fill; Shortlist count 1; toggled back to 0 |
| Library | Font overlay start/end | LIVE PASS | Overlay 1797 sheet shows reference style and End overlay; End overlay restores cards |
| Library | Tools menu | LIVE PASS | Menu exposes Tags, Families, Duplicates, Font Health, Google Fonts, Activation, Folders, Metadata table, backup actions and Select visible families |
| Library | Tag/property search popover | LIVE PASS | Tag button opens Search filters with include/exclude modes and properties; selecting Variable applies `#fontshelf/variable` and returns 85 families; cleared |
| Library | Tag filter combine mode | LIVE PASS | Tag filters popover exposes AND/OR; Any included toggled live; dismissed with no tags |
| Library | Filter icon advanced panel | BLOCKED | Clicking the line.3.horizontal.decrease.circle control produced no AX state change in the isolated runtime, so the panel could not be verified through Luna |
| Library | Source filter | LIVE PASS | Menu exposes All sources/User-third-party/System; User-third-party reduces result to 476 families; restored All sources |
| Library | Sort | LIVE PASS | Menu exposes Name A–Z, Name Z–A, Most styles, Category; Most styles surfaces Recursive (71 styles); restored Name A–Z |
| Library | Variable fonts checkbox | LIVE PASS (Tools agent) | The separate Tools pass toggled this checkbox; see QA_TOOLS_MATRIX.md. Earlier lock-only blocker is obsolete. |
| Library | Preview-character checkbox | LIVE PASS | Toggled from Value 1→0 and back to Value 1 after clearing the temporary search. |
| Library | Appearance popup | LIVE PASS | Dark→Light changed the popup value to Light; restored Light→Dark. |
| Library | Add font folder / Live folders | LIVE PASS (Tools agent) | Exact disposable fixture folder added, watched, and stopped; see QA_TOOLS_MATRIX.md. Refresh command was not separately verified. |
| Library | Keyboard search field | LIVE PASS | Search text field received setValue and updated results/clear affordance |
| FontInspector | Open family style inspector / All styles | LIVE PASS | Style sheet opens with style selector and six inspector tabs; changing the Style popup was verified in the follow-up below |
| FontInspector | Preview tab text and size | LIVE PASS | Preview text changed to QA glyph preview; Increment changed 64→78.4; Decrement/text restore returned 64 and default text |
| FontInspector | Glyphs tab | LIVE PASS | Glyph collection exposes Unicode labels and Group popup |
| GlyphBrowser | Unicode lookup `U+0041` | LIVE PASS | Filter leaves one LATIN CAPITAL LETTER A U+0041 result |
| GlyphBrowser | Select glyph, Metrics and Outline | LIVE PASS | Selected glyph reports `· A`; both checkboxes enabled; metric labels visible; Export SVG enabled |
| GlyphBrowser | Copy character affordance | LIVE PASS | Copy character completed; inspector status changed to “Character copied”. Clipboard was not pasted into Notes to avoid modifying the user’s existing note. |
| FontInspector | Waterfall | LIVE PASS | 10, 12, 14, 18, 24, 36, 48, 72, 96 pt samples visible |
| FontInspector | Body layout text, steppers, columns, alignment, width, leading, tracking | LIVE PASS | Headline and body text changed then restored; body/heading steppers and all three sliders were incremented/decremented; columns 2→3→2; alignment Left→Center→Left. |
| FontInspector | OpenType feature values and reset | LIVE PASS | dlig Default→On changed the row value to On; Reset features returned it to Default. |
| FontInspector | Context Show in Finder and Copy path | LIVE PASS | Copy path and Show in Finder actions were invoked from the live metadata panel. |
| FontInspector | Adobe target selection, script export, temporary activation | LIVE PASS | Target Illustrator→Photoshop→Illustrator; exported `QA-Photoshop.jsx` to the disposable fixture folder; activation reported “Already available to other apps. No activation changed.” |
| FontInspector | Style popup and per-style selection | LIVE PASS | Style popup changed COMPRESSED_V2→MEDIUM_V2 and displayed MEDIUM_V2. |
| GlyphBrowser | Glyph Group popup and SVG file export | LIVE PASS | Group All glyphs→Numbers→All glyphs; selected U+0041; exported `QA-glyph.svg` to the disposable fixture folder and status reported “SVG exported”. |
| Library | Collection create and rename | LIVE PASS | Created `QA Disposable Collection`, renamed it to `QA Collection Renamed`, and observed the new name in the collection list. |
| Library | Collection delete | BLOCKED | Two native attempts (Backspace and Delete) did not expose deletion; Delete left the inline Name field, so no destructive action was guessed. |
| Library | Variable axes | BLOCKED | Recursive variable family opened successfully, but its family inspector and Edit family tool exposed no axis controls; Edit family exposed grouping only. |
| Library | Overlay Reference style popup | LIVE PASS | Recursive overlay opened; Reference style changed Regular→Mono Linear and End overlay restored the Library. |
| App menu | About FontShelf | LIVE PASS | About dialog shows FontShelf QA Version 0.20.0 (28); closed afterward. |
| App menu | Privacy… | LIVE PASS | Privacy alert opened and displayed local-storage, GitHub preview/download, folder access, export, and Adobe-script handling text; dismissed with the dialog action. |
| FontInspector | Close/restore | LIVE PASS | Done closes sheet and restores Library with disposable state cleared |
| Build/self-test | `bash build.sh` and built-in self-test | AUTOMATED PASS | Build completed in isolated copy; self-test output saved at `/tmp/fontshelf-selftest.log` and reports all PASS lines including 180 families / 528 styles classification |

## Gaps and limitations

- The Filter icon itself produced no accessibility-tree change when clicked during this pass; the Tag filters popover and property-search flow are live and functional. This is recorded as a UI affordance gap rather than claiming the icon is verified.
- Remaining blocked controls have concrete evidence: collection deletion was not exposed by Backspace/Delete; family Inspector could not be opened because View List/Grid commands left a 100-row table, row click/double-click and keyboard selection had no effect, and Font→Inspect Selected Family was disabled; Add font folder, Live folders, and Refresh were intentionally skipped as system-affecting operations.
- Physical trackpad gestures, native drag-out glyph export, VoiceOver navigation, every window size, external Adobe execution, and real font activation were not performed.
- Existing QA notes cover broad library tools and destructive/system operations; this matrix records the fresh runtime evidence above and does not treat static review as verification.
