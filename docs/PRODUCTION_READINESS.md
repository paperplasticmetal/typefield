# Typefield production readiness audit

Updated 2026-10-01 for the 0.59.4 local build. [0.59.4 QA](QA_2026-10-01_0.59.4.md) records compact Spaces polish, responsive checks, installation and saved-state verification. [0.59.3 QA](QA_2026-10-01_0.59.3.md) records the five template compositions, and [0.59.2 QA](QA_2026-10-01_0.59.2.md) records the large-preview grid replay, Spaces copy/color checks and performance measurements. Distribution signing and the broader interaction matrix are pending. The 0.47 and 0.40 findings below remain historical evidence; they are not fresh verification of this build. The [release UX review](RELEASE_UX_REVIEW_2026-09-29.md) records the prior interaction changes, and the [roadmap](ROADMAP.md) tracks product depth separately.

## 0.59.4 compact Spaces polish

Responsive default-format checks cover right-edge Website navigation, visible Product UI Save text and aligned summary values, the compact Poster program, and the Type system numeral label. A legacy Website navigation override remains a single text frame. PDF previews at 320, 390 and 960 px were visually reviewed; saved projects were not changed.

## 0.59.3 Spaces composition refinement

Website, Product UI, Editorial, Poster and Type system now use different content structures and visual rhythms. Website and Editorial use lightweight vector illustrations so their PDF and editable handoffs retain the composition. Responsive checks cover default layouts down to 320 px, text-frame fit, section reordering, saved Editorial continuation placement and Poster rail contrast with matching dark accent/ink colors. Saved boards are not migrated or rewritten.

## 0.59.2 release refinement

Library rows now align their cards at large preview sizes, including the 133-point single-letter case that regressed. New Spaces canvases use neutral white paper, while saved choices remain unchanged. UI and handoff copy avoid centered-dot spacers. A disposable 2/50/200-typeboard navigation audit and a small Library footer optimization address the reported sluggishness without weakening Spaces persistence. The [market-positioning review](MARKET_POSITIONING_2026-10-01.md) rejects an unverified first-of-its-kind claim and defines the connected three-workspace message.

## 0.59.1 compact visual work

Library cards spend less vertical space on short previews and keep full style counts. Spaces leaves a visible margin around Fit-width canvases and strengthens selected/scope states. Letterform Editor compacts empty proofing, exposes metrics in a disclosure at narrow widths and keeps its controls aligned from the top. The [0.59.1 QA note](QA_2026-09-30_0.59.1.md) records the installed compact layouts and public-release gates.

## 0.59.0 candidate interaction work

| Area | Source change | Verification still needed |
| --- | --- | --- |
| Library | Saved-search preview and coverage text stay together; metadata rows use matching styles; batch scope and hidden selection are explicit; collection deletion is discoverable and confirmed. Backup merge shows a contents summary; Notes saving uses rollback on failure. | Reopen a saved coverage search after changing preview text; inspect style-filtered cards and table; perform batch selection and collection create/delete with disposable data; force a Notes write failure. |
| Spaces | Edit scope, export omissions and unavailable fonts are explained before handoff; imports summarize contents and warnings; Space deletion registers Undo; the 50-checkpoint limit is visible. | Exercise each export format and imported/native canvas mix, an unavailable font, image omission, import warnings, Delete/Undo/Redo and checkpoint rollover in a disposable project. |
| Letterform Editor | Drawn/empty character filtering and jump, a resizable proof strip, current-glyph Edit-menu history, and export scope are exposed. SVG import states its tracing limit. | Check selection/focus, keyboard Undo/Redo, short-window proofing, partial TrueType export, SVG import and actual exported glyphs in other apps with disposable projects. |

Missing-letter generation remains hidden while its research implementation is retained. The 85% native-vector objective was not reached and is not a release claim.

## Changes in 0.47.0

| Risk or gap | Change | Verification scope |
| --- | --- | --- |
| A crash between backup-import file replacements could leave Library, Spaces, advanced settings and Letterform Editor in different versions | Stage old and new copies, publish a durable transaction journal before writing targets, and recover on next launch. If copies or journal cleanup cannot be verified, preserve them and block editing. | Interrupted-write and obstructed-recovery fixtures in the native suite; a real power-loss test remains external validation. |
| Selected imported shapes had no stroke controls | Add stroke color and width to saved layers, canvas/PDF rendering, proportional canvas scaling, and supported Figma/Adobe interchange. | Native model/export and mocked Figma bridge checks; live editor and Adobe/Figma application checks remain open. |
| A readable local watched folder could be reported as an expired sandbox permission | Distinguish local and sandboxed bookmark behavior, report unavailable folders separately, and replace the old saved path when a folder is chosen again. | Disposable local-folder fixtures; final signed sandbox, offline volume and session activation checks remain open. |

## Earlier release risks addressed in 0.40.0

| Risk | Change | Verification |
| --- | --- | --- |
| Xcode project omitted newer Swift source files although the script build included them | Added the floating inspector, editor session, shortcuts, shortcut reference, and download checks to the Xcode target | Source membership audit and unsigned Release archive |
| Backup export could silently turn unreadable Library, Spaces, or advanced settings into default data | Block export before opening the save panel when any saved source is unreadable or invalid | Disposable corrupt-file checks |
| Backup merge could write some saved files and fail on a later file | Stage encoded data, preserve previous files, and roll back attempted writes and in-memory state on ordinary failure; assign new IDs to imported nested canvases/checkpoints | Injected late-write failure and corrupt-source checks |
| Failed favorites, categories, collection changes, or family edits could leave unsaved state visible | Restore prior in-memory state on failed saves; restore the first file if a family edit's second save fails | Disposable write-failure checks |
| Failed Spaces creates, imports, edits, or deletes could leave visible unsaved state or an undo entry | Persist the operation before publishing its result; roll back state and editor drafts on failure; create a first space and board together | Disposable blocked-parent write checks |
| Interrupted Google Fonts updates could replace part of an existing managed folder | Stage every licensed file, validate it, swap complete folders, and restore the old folder if the Library save fails | Disposable old-folder and forced-save-failure checks |
| Imported JSON or a linked saved-data path could consume excessive memory or read the wrong file | Bound local imports by format, reject special files and symbolic links, validate aggregate Figma layers/text, and reject linked Library/Spaces/Letterform save paths | Oversize, malformed-name, and symlink fixtures; Figma bridge tests |
| Imported shapes lacked direct appearance controls | Added selected-shape fill, opacity, and corner radius with single-shape scope and Undo | Native model/export checks; direct control interaction remains manual QA |
| Generated developer handoff still carried the old visible name | Changed the displayed heading to Typefield; retained versioned interchange identifiers for old handoffs | Native handoff assertion |

Backup import now includes next-launch recovery. The recovery checks protect local saved files on the exercised interruption paths; a real power-loss run and an upgrade on another Mac remain open validation.

## Open release validation

1. **Clean and upgrade installs.** Use disposable macOS accounts on another Mac, including macOS 13. Exercise a new Library, old FontShelf-to-Typefield upgrade, Store-container migration, external-folder permission renewal, managed font licenses, backup restore, and recovery from an unavailable or relocated volume. Current same-machine fixtures do not prove these flows.
2. **Current-version hands-on workflow matrix.** The [0.47 focused QA record](QA_2026-09-23_0.47.md) covers an earlier shape-stroke and local watched-folder path. Review the 0.59 changes above in the installed candidate, then test small-window layout, VoiceOver, keyboard-only navigation, object selection and dragging, Shift resizing, Undo, numeric and color controls, pinch/scroll, and actual drag/drop. Use disposable Library and project data.
3. **Real host-application bridge fidelity.** Run the generated Illustrator/InDesign builders and return bridge in supported Adobe versions, and exercise Figma package import/export in Figma. Compare wrapping, leading, variable axes, OpenType settings, shape appearance, unsupported effects and missing-font behavior. JSON/JSX fixtures and local bridge tests are narrower.
4. **Artwork and font proofing.** Test actual Procreate-produced documents, diverse alphabet sheets, and exported fonts in other apps. Current synthetic fixtures cover format safety and common geometry, not broad real-artwork quality.
5. **Public product details.** Complete independent Typefield name clearance, set final public support/privacy destinations, and capture current storefront screenshots and feature copy. The [rebrand plan](REBRAND_PLAN.md), [privacy copy](PRIVACY.md), and historical [screenshots log](SCREENSHOTS.md) are starting points, not clearance evidence.
6. **Library permission and activation behavior.** The local false-renewal path is covered by a disposable fixture. Test actual bookmark revocation, relocation, offline volumes, sleep/wake, session activation and guarded original-file repair under final sandbox entitlements. Track as [LB-01](ROADMAP.md).
7. **Distribution identity and public access.** Verify the final team-signed archive, production bundle ID, App Store Connect/TestFlight installation, support/privacy URLs and storefront listing. The local 0.59 candidate does not establish distribution readiness.

## Product gaps to decide deliberately

These are meaningful capability limits, but the existing feature should be described truthfully rather than treating all competitor features as launch gates.

| Area | Highest-priority gap | Current honest scope |
| --- | --- | --- |
| Letterform Editor | [FL-03](ROADMAP.md) direct outlined-SVG path import; production master interpolation and variable-font export | Drawn and imported outlines are editable. SVG artwork is rendered and traced into new curves, so source control points and groups are not retained. Missing-letter generation is hidden. |
| Spaces | [SP-02](ROADMAP.md) local typography override and reset for native template text; remaining [SP-03](ROADMAP.md) selection and transform consistency | Native role typography is shared across its uses; imported text layers are individually editable. The 0.59 source candidate labels this scope. |
| Library | [LB-01](ROADMAP.md) signed-sandbox permission and activation QA; later [LB-02](ROADMAP.md) document-triggered activation and [LB-03](ROADMAP.md) collection migration | Local watched-folder recovery is improved, and manual session activation exists; other apps do not trigger activation automatically. |

The rest of the roadmap includes optional professional/editor depth, research items, and strategic cloud/team features. Those should not be advertised as shipping capabilities.

## Security applicability

Typefield is a local macOS app with local JSON project files and outbound catalog/download requests. It has no account service, login/signup, application database, Firebase/Supabase backend, admin routes, or browser-hosted production API. Authentication, server-side user-ID checks, database row isolation, SQL/NoSQL injection, login rate limits, security headers, and CORS are therefore not application controls in this build. They become mandatory design work before adding any hosted account or collaboration feature.

The relevant surface is local file and interchange trust: repository secrets, `.env` handling, sandbox/file permissions, bounded Figma/Adobe/artwork imports, unsafe paths and symbolic links, external downloads, private error/log content, and tests with deliberately malformed inputs. See [security policy](../SECURITY.md), [privacy](PRIVACY.md), and the security findings recorded in [status](STATUS.md).

| Requested security check | Disposition for this build |
| --- | --- |
| API keys, `.env`, hardcoded secrets, Git history | No service credential is required by the app. Local environment/signing files are ignored. A pattern scan of 515 historical text blobs and 99 current source/text files found no candidate private keys or common token formats; pattern scans cannot prove that no secret of any kind ever existed. |
| Authentication, server-side permission and user-ID checks, login/signup rate limits, admin routes | No Typefield account, public API, login, or admin service exists. Add these controls before any future hosted sync or collaboration work. |
| User isolation, database, Firebase/Supabase/storage, SQL/NoSQL injection | The app saves its own local files and user-selected folders; no hosted database or query language is present. The distribution target uses App Sandbox and user-granted file access. |
| Production debug mode and detailed errors | No production debug web endpoint exists. Error messages stay in the local app for recovery; no analytics or project-content upload service is present. Release build configuration and private-output handling remain part of archive review. |
| Input validation, sanitization, file uploads, untrusted-user tests | Local Figma/Adobe/space/backup JSON and artwork are the equivalent of untrusted uploads. Bounded regular-file reads, model and aggregate limits, path checks, and malformed fixtures cover these paths. SVG artwork rejects external resources/DOCTYPE; Procreate ZIP parsing limits decompression. Downloaded fonts are staged and validated before replacing an existing managed folder. |
| Security headers and CORS | There is no browser-hosted Typefield service or HTTP response surface. The Figma plugin runs inside Figma's plugin environment, denies network in its manifest, and passes JSON through its documented local bridge. |
