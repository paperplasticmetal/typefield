# Privacy

Typefield stores collections, tags, notes, settings and folder bookmarks locally. It has no account system, advertising, analytics or tracking. It does not upload your fonts, preview text or library.

Browsing Google Fonts loads public preview files from Google's font repository on GitHub. Downloads also retrieve the supplied license. GitHub receives normal connection information such as IP address and the requested public file path. Preview text is rendered locally and is not part of those requests. Remote previews use an ephemeral network session without a disk cache and an in-memory font cache; explicit downloads save files locally.

The direct-download app checks https://typefield.app/updates/appcast.xml for signed published updates once a day when automatic checking is enabled. Update downloads come from the public Typefield GitHub releases. These services receive standard connection information, and the updater identifies the app version and operating system in its request. Optional system profiling is disabled. Fonts, library content, preview text and projects are never included. Users can disable automatic checks or check manually in Settings → Updates. App Store builds do not embed the direct-download updater.

The sandbox build obtains folder access through macOS pickers. Font exports are written to a user-chosen destination. Adobe scripts are saved for manual execution; Typefield does not control other apps.

Only use or export fonts and artwork you have permission to use. Typefield does not verify whether a font license allows redistribution, web embedding, app embedding, or commercial use. Figma, Adobe and developer handoffs refer to fonts by name and do not include the font binaries.

This document describes the current implementation. Before Store submission, publish an owner-approved privacy policy with a support contact and keep App Store privacy answers consistent with the app and its network services.
