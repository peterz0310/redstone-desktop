# Stability work — October 12, 2026

The audit of `f28f9b9` reproduced two current failures using isolated fixtures and found two persistence weaknesses. The following changes address those findings. Test stores/preferences, offline audio and native reset harnesses are isolated from the owner's saved worlds and game imports.

## Changes and regression coverage

| Finding | Change | Automated evidence |
| --- | --- | --- |
| Audio-device notification entered a main-actor callback on an engine thread, causing SIGTRAP | Schedule downstream delivery onto the main queue before entering the sink; teardown remains asynchronous | A background notification stops a playing offline graph safely, then the next effect renders audio. The same standalone probe that previously exited 133 now exits 0. |
| Circuit edits could publish a library over the disk/export limit | One aggregate encoding contract checks candidates before model/history/runtime changes, covering editor and desktop build placement, paste, dust/terrain strokes, configuration, lever state, and world/area metadata | Two realistic 3,000-component blueprint pastes accept the first and reject the second without partial edits; independent-world aggregate limits, exact-cap ordinary placement/configuration, build strokes, lever state, undo and disk round trips are covered. The original 6,000-button probe now returns false and preserves the saved world. |
| Quit ignored a failed save | `AppTerminationDelegate` uses AppKit's deferred termination decision; Command-Q and menu Quit share it. Users can stay open, retry, or save a verified recovery copy before exit | Injected disk-full errors cover cancellation, retry, failed/cancelled recovery, successful importable recovery, and emergency preservation of an oversized older snapshot. The reset/relaunch harness checks that old shutdown cannot resurrect reset data. |
| Save-size checks allocated entire oversized files | Open nonblocking, verify a regular-file descriptor and its size, then cap chunk reads even if it grows. Reuse for current/legacy saves, imports, blueprints and reset journal/preferences | Sparse 64 MB files are rejected and preserved; exact-bound reads succeed, over-bound reads fail, and directories/pipes are refused without blocking. |
| Invalid custom-pack replacement discarded the working appearance | Publish the source/pack/preference only after successful loading; failure retains texture cache, sounds and revision | A refused replacement preserves the working texture identity, sound overrides, source, name, warnings and remembered choice. |
| Older SpriteKit child-attachment exception during editor initialization/layout | Guard size callbacks until initialization finishes; attach owned layers once and rebuild only checker geometry during viewport changes | Native SKView resize/pan coverage preserves each layer's identity and editor overlays. The 600-step rendering probe completes without a crash. This is ownership hardening; the historical exception itself was not reproduced. |

No private macOS APIs were added. Audio delivery follows Apple's [engine configuration notification guidance](https://developer.apple.com/documentation/foundation/nsnotification/name-swift.struct/avaudioengineconfigurationchange); Quit uses [applicationShouldTerminate](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationshouldterminate(_:)). Simulation still has no SpriteKit dependency, Finder access remains behind its provider, and action execution remains separate from rendering/simulation.

## Results

- Debug application build: passed.
- Full XCTest suite: **604 tests, zero failures** (15 additional regression tests). The first full run identified old assertions expecting the previous root-node layout; those expectations were updated and the complete rerun passed.
- Recompiled original background-audio and oversized-circuit probes: corrected behavior, exit 0.
- Recompiled 64 MB sparse-save probe: refusal in about **0.12 ms**, peak RSS **28.45 → 28.59 MB**. The audited loader allocated the whole file first, increasing peak RSS by about 64 MB. These are isolated-process measurements, not a production memory guarantee.
- Recompiled renderer probe: **600 iterations**, about **3.35 seconds**, at most **12 retained chunks**, peak RSS **30.86 → 57.55 MB**, worst update about **58.7 ms** including cold work. No crash. This does not prove sustained GPU/battery behavior or eliminate every possible rendering failure.

- Native reset/relaunch smoke: passed. A distinct isolated native app showed Setup with one empty world, Desktop stopped and no Finder read; child shutdown preserved the fresh library and the validated backup.
- Universal **arm64 + x86_64 Release** build: passed. Both the app bundle and ZIP passed identity, macOS 14 target, permissions, icon/notices and no-saves/imports/scripts verification. The local package is unsigned and not notarized.

## Remaining physical validation

The real audio route/device and sleep/wake checks, normal quit/reopen acceptance, invalid-pack UI choice and prolonged editor/Desktop session are deliberately unconfirmed in [TESTING.md](TESTING.md). Do not fill the real disk to exercise failure handling; injected failures cover that policy in tests.

The separate October 11 SpriteKit report predates later rendering changes, and the exact historical binary/dSYM mapping is unavailable. If a child-attachment exception recurs, retain the crash report and the exact app build/dSYM. Do not infer that it is the audio-device failure. Two other reports came from XCTest-host task/autorelease machinery; no current app-source cause was reproduced, so no speculative framework workaround was introduced.

Ordinary Quit can postpone termination, but Force Quit, power loss or termination that bypasses the application decision can still lose pending work. Save/encoding remains synchronous and bounded; a large library can consume some UI frame budget. See [RECOVERY.md](RECOVERY.md) for recovery-copy limits and restoration.

## Release preparation follow-up — October 12, 2026

Native offline Help and About copyright/version metadata were added. Guides now describe the implemented five-step setup, current 49-texture custom-pack contract, buildable stone ores, multi-display behavior and preserved appearance after a failed replacement. Install instructions, preview release notes and an unresolved-only public-release checklist accompany packages. Automated Markdown checks cover local links, anchors and images in the source tree and actual customer payloads.

Validation after these changes:

- Debug build and **605 XCTest tests: zero failures**. The initial Help fitting-width test exposed an unconstrained 1,555-point ideal width; its viewport now constrains wrapping and the complete rerun passed.
- **12 Python release-tool tests: passed**, including archive traversal/case collisions/duplicates/symlinks, Mach-O slice integrity, imported-data exclusion, docs/image/anchor failures, checksums, actual texture/sound documentation contracts and refusal of development signing identities.
- Universal Release app, customer ZIP and **HFS+ DMG: passed**. The actual DMG was checked and mounted read-only without opening the app/Finder, its Applications shortcut/docs/app were verified, and it was detached. An initial quiet/default-filesystem creation exited without a diagnostic; isolated fixtures worked and explicit HFS+ creation with visible diagnostics completed. No private workaround or owner-data change was introduced.
- App/dSYM UUIDs match for both architectures; symbols are archived separately and checksums/build provenance accompany customer packages.
- GitHub CLI has no authenticated session, so hosted CI could not be checked. No Developer ID Application certificate was found. Signing/notarization, downloaded-copy Gatekeeper acceptance, minimum-OS/Intel execution and the remaining Mac sessions are **unverified**, listed in [RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md). No release was uploaded or published.
