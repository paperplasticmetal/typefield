# Shelved: New from fonts

Shelved at the product owner's request on 2026-09-21. Combining installed font faces is not currently offered in Typefield. This is a product-scope decision, not a legal conclusion about every possible source license.

`FontLabRemixView.swift` is retained here for possible future work and excluded from the Swift package, native build and Xcode target. The workspace buttons, sheet presentation, source-selection wiring and specimen CLI entry point have been removed. Do not re-enable the feature without a new product decision.

`Sources/FontLabRemix.swift` retains the existing-project provenance types, geometry shared by artwork tracing/export, and regression coverage. Saved projects and their attribution remain readable and editable; no user data is removed. Drawing, artwork import, outline editing and export continue normally.

If revisited, first define which source artwork and licenses the product will accept, then review quality and UX before restoring the entry points. The previous complete implementation is also available in Git history at `3a23907`.
