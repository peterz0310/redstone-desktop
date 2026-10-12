# Before publishing 0.1.0

The current packages are local review builds, not a public release. Completed automated checks are recorded in [STABILITY.md](STABILITY.md) and the build logs; they do not complete these physical or distribution gates.

- [ ] MANUAL: Test the packaged app after copying it to Applications, with one app instance running. Check setup, native Help, menu controls, a harmless folder Output, saving/quit/reopen, and your existing worlds/imported assets.
- [ ] MANUAL: Complete the audio-device/sleep/wake and prolonged editor/Desktop checks in [TESTING.md](TESTING.md#stability-fixes-2026-10-12). Retain the exact app, symbols ZIP and crash report if a problem recurs.
- [ ] MANUAL: Rehearse export/import and Start Over/backup restoration using disposable data or a separate macOS account. The owner's backup/reset acceptance is still deferred; automated reset fixtures are separate evidence.
- [ ] MANUAL: Test the minimum supported macOS 14 and Intel execution, or revise the advertised support range to match tested systems before publishing. A universal binary alone is not Intel runtime validation.
- [ ] MANUAL: If advertising multiple displays, finish physical Finder mapping/Spaces/reconnect checks. Build Mode edits only the primary display.
- [ ] MANUAL: Install a Developer ID Application certificate/private key, sign the app and DMG, submit the exact DMG for notarization, staple/validate its ticket, and test Gatekeeper acceptance of a downloaded copy. Apple Development signing is not public Developer ID distribution.
- [ ] MANUAL: Record a passing hosted CI run; the workflow is configured but a local run is not GitHub execution.
- [ ] MANUAL: Review the version/build, release notes and checksum/manifest; retain matching symbols privately. Publish only the final signed/notarized installer, with accurate preview/support wording and a real download link. No public download/tag has been created by these local tasks.

Follow [RELEASE.md](RELEASE.md) in order. Never change source or rebuild between notarization submission and stapling. Keep local game imports out of all artifacts. Gatekeeper checks require the real signed/downloaded package; do not disable security checks to get a passing result.
