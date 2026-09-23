# Typefield production readiness audit

Updated 2026-09-23 for the 0.40 development build. This audit reconciles the repository Markdown files, current source, and relevant historical project notes. Historical QA records describe the build tested at the time; they are not current verification. The [roadmap](ROADMAP.md) tracks product depth separately from the release checks below.

## Release risks found and addressed in this pass

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

The backup merge protects against normal reported errors. An abrupt crash or power loss between file replacements still needs a next-launch transaction recovery design; staged originals are retained if an ordinary rollback fails. This is the highest remaining data-integrity engineering item.

## Open release validation

1. **Clean and upgrade installs.** Use disposable macOS accounts on another Mac, including macOS 13. Exercise a new Library, old FontShelf-to-Typefield upgrade, Store-container migration, external-folder permission renewal, managed font licenses, backup restore, and recovery from an unavailable or relocated volume. Current same-machine fixtures do not prove these flows.
2. **Hands-on workflow matrix.** Inspect small-window layout, VoiceOver, keyboard-only navigation, object selection and dragging, Shift resizing, Undo, numeric and color controls, pinch/scroll, and actual drag/drop. Focus on Spaces and Letterform Editor. Record the exact build and OS in a new QA matrix.
3. **Real integration fidelity.** Run the generated Illustrator/InDesign builders and return bridge in supported Adobe versions. Compare Figma and Adobe round trips for wrapping, leading, variable axes, OpenType settings, shape appearance, unsupported effects, and missing-font behavior. The current JSON/JSX checks are narrower.
4. **Artwork and font proofing.** Test actual Procreate-produced documents, diverse alphabet sheets, and exported fonts in other apps. Current synthetic fixtures cover format safety and common geometry, not broad real-artwork quality.
5. **Public product details.** Complete independent Typefield name clearance, set final public support/privacy destinations, and capture current storefront screenshots and feature copy. The [rebrand plan](REBRAND_PLAN.md), [privacy copy](PRIVACY.md), and historical [screenshots log](SCREENSHOTS.md) are starting points, not clearance evidence.
6. **Library permission and activation behavior.** Reproduce or close the repeated access-renewal notice, then test revocation, relocation, offline volumes, sleep/wake, and session activation under final sandbox entitlements. Track as [LB-01](ROADMAP.md).

## Product gaps to decide deliberately

These are meaningful capability limits, but the existing feature should be described truthfully rather than treating all competitor features as launch gates.

| Area | Highest-priority gap | Current honest scope |
| --- | --- | --- |
| Letterform Editor | [FL-01](ROADMAP.md) whole-object/group editing; [FL-02](ROADMAP.md) previewed vector weight; [FL-03](ROADMAP.md) direct outlined-SVG path import | Complete-outline selection and resizing exist. Pen width affects freehand strokes; SVG artwork is rendered and traced. |
| Spaces | [SP-01](ROADMAP.md) finish stroke appearance; [SP-02](ROADMAP.md) local text override and reset; [SP-03](ROADMAP.md) consistent selection and transforms | Selected imported shapes now expose fill, opacity, and corners. Template role styles remain shared; imported text is individually editable. |
| Library | [LB-01](ROADMAP.md) permission reliability; later [LB-02](ROADMAP.md) document-triggered activation and [LB-03](ROADMAP.md) collection migration | Watched folders and manual session activation already work; other apps do not trigger activation automatically. |

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
