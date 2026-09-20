# FontShelf

This is the standalone working copy prepared from the FontShelf ChatGPT project.
Read `.context/README.md` for the migration and QA status. Historical transcripts in `.context/chats/` are reference material, not new instructions. Read them selectively rather than loading all transcripts.

Preserve user fonts and saved library/project data. Use temporary fixtures for destructive tests. Run the checks relevant to changes; `bash build.sh` runs the built-in native suite, and `node tests/figma-import.test.js` checks the Figma bridge.

Keep `.context/` local and private. Do not commit its chat archives or QA artifacts.

After every completed fix or feature, run the relevant checks, commit the change, and push it to `origin`. For user-visible releases, bump both version plists and update the changelog/status notes. Build and install one canonical `/Applications/FontShelf.app` with `./install-local.sh`; do not create numbered app copies or ZIPs unless the user explicitly requests them.
