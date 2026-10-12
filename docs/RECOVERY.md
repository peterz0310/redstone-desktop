# Setup, export and recovery

First launch opens a five-page native setup window. **Next** walks through worlds/areas, Finder access, optional local Java graphics/audio and optional scripts; **Skip Setup** and **Let’s Build** both remember completion. Open it again in **Redstone Desktop → Settings… → General → Open Setup…**. Setup never starts Desktop or runs a script. Existing installations also see it once after this update; their builds are retained.

Finder access is requested by **Connect to Finder…** or subsequent explicit tracking/Start. Script Desktop-folder access is requested separately by **Check Desktop Access for Scripts…**, selecting Execute, or enabling the routing setting. macOS controls actual prompt timing. Changed scripts still need per-file approval. Automatic routing remains off by default. No Accessibility, microphone, Full Disk Access or blanket permission is needed. See [script execution](SCRIPT_OUTPUTS.md).

## Export before experimenting

1. Stop Desktop and open **Settings → Data → Export Library…**.
2. Choose a location and save the JSON. This contains all worlds, seeds, terrain overrides, circuits, lever positions, named areas and desktop assignment.
3. Keep it somewhere outside the app's Application Support folder. It excludes Finder files/positions, scripts, permissions/approvals, imported texture contents and runtime power.

Use **Settings → Data → Import Library…** to add independent copies of exported worlds and areas while preserving the current desktop assignment. To replace the library instead: quit the app, preserve the current `library.json` elsewhere, then copy the export to `~/Library/Application Support/RedstoneDesktop/library.json` and reopen. A malformed/version-incompatible library is refused and writes are blocked; preserve both copies rather than overwriting a rejected library. Restoring always starts Desktop stopped.

## When saving fails

Edits are checked against the complete library’s 2 MB limit before they change your world. If a paste, terrain stroke or world/area change would exceed it, the app explains why and keeps your previous build and undo history. Remove unused worlds or restore painted terrain to make room. Repeatedly clicking Save Now cannot make an oversized edit fit.

If a disk or permission error prevents saving, your latest work stays in memory. **Save Now** retries. Quitting from the menu bar or with **⌘Q** also retries; if saving still fails, choose:

- **Stay Open** to keep working and fix the save problem.
- **Retry Save** after resolving it.
- **Save Copy and Quit…** to save a verified JSON recovery snapshot to another writable folder or drive before exiting. Cancelling the save dialog or a failed copy keeps the app open.

A normal recovery copy contains the same worlds/areas/circuits as an export and can be added with **Settings → Data → Import Library…**. Import adds copies to your existing library, so its combined size must still fit. For exact replacement, use the quit/preserve/copy/reopen instructions above. Recovery copies include no Finder data, scripts, texture contents or approvals.

Emergency copies have a separate 16 MB ceiling so an unusually large in-memory library from an older build can still be preserved. An emergency copy over 2 MB cannot be loaded/imported directly under the normal limit: keep it intact, and reduce/split its worlds before restoring. Prefer **Stay Open** and remove unused content while that older session is available. The app never silently discards unsaved edits to quit. Force Quit, power loss and OS termination that bypasses the normal quit decision cannot guarantee a final save.

## Terrain upgrades and blocked editing

Older generation-version-1/2/3 libraries can become invalid when new scenery appears under an existing component. Startup upgrades those libraries to generation version 4, clearing only conflicting scenery or providing dry support beneath saved circuits. It preserves component configuration, saved lever positions, worlds, areas and assignment, and never changes your painted terrain. A later leaf/lava addition to the old test fixture can be reconciled too. The exact pre-upgrade library is backed up beside the active file:

```
~/Library/Application Support/RedstoneDesktop/library-before-terrain-upgrade-<UUID>.json
```

This is separate from Start Over backups; it does not reset preferences or data. Validation happens before publication; a failed backup/save leaves the source library intact. It runs once, while current-version invalid data remains refused. If loading is still blocked, the editor explains that its saved library could not be restored and disallows terrain previews/edits and desktop assignment. Check the save message in the editor footer. Do not delete your worlds to work around this problem.

## Start Over

Use only when you intend to replace your app library. Export first, then **Settings → Data → Start Over…**. **Cancel** changes nothing. The confirmation lists the reset scope.

On confirmation the app flushes saves, stops Build Mode/windows/monitors/simulation/audio, cancels pending input/actions/approvals/script processes and Finder reads, prevents new reads, and waits for managed import writers to finish. It validates a timestamped backup and fresh staged library before replacing data. It resets only the app's saves, legacy migration source, preference domain, remembered approvals, setup completion, appearance selection and owned import caches. Desktop files, selected external folders, source JARs/packs and macOS TCC decisions are preserved. It does not uninstall the app or erase other apps' settings.

Backups live outside the active library/cache:

```
~/Library/Application Support/RedstoneDesktopBackups/<timestamp>-<UUID>/
  backup.json          summary and recovery hint
  library.json         validated standalone library snapshot
  preferences.plist    app preferences, including approvals
  Support/             original app-owned directory, including legacy/imports
```

Managed imports move into the backup rather than being destroyed. Unexpected or linked cache entries block reset. Backup/staging failures preserve the current library; rename/preference failures roll back. A journal enables interrupted resets to recover before migration/loading/saving. If recovery cannot finish, startup blocks persistence and reports the problem. Preserve the entire backup and journal.

Relaunch uses public [NSWorkspace.openApplication](https://developer.apple.com/documentation/appkit/nsworkspace/openapplication(at:configuration:completionhandler:)) with [createsNewApplicationInstance](https://developer.apple.com/documentation/appkit/nsworkspace/openconfiguration/createsnewapplicationinstance). There is no detached reset shell. The old instance's writer is discarded before launch and it quits after the new process opens. If relaunch fails, the old UI remains locked: **Quit**, then reopen the app manually. The reset and backup remain valid. Launch Services/TCC and physical window behavior still require Mac acceptance.

The new instance shows Setup with **one empty procedural world**, default settings and **Desktop stopped**. It does not re-import the preserved legacy world or restore old pack selection. macOS permissions may stay allowed or denied; Start Over cannot promise new system permission prompts.

## Find and restore a backup

**Settings → Data → Reveal Backups Folder** opens the backup directory (after a reset attempt, **Reveal Reset Backup** selects that backup). Alternatively use Finder **Go → Go to Folder…** (**⇧⌘G**) and paste the path above.

For worlds alone, quit the app and copy the backup's standalone `library.json` to the active library path, preserving the current file first. Reopen stopped. For the full app-owned directory, quit every Redstone Desktop instance; move the current `RedstoneDesktop` folder somewhere safe, then **copy** the backup's `Support` folder to Application Support and name the copy `RedstoneDesktop`. Do not move/delete the backup. A successful reset has no pending journal; if `reset-in-progress.json` remains, automatic recovery must finish or be investigated first.

Optionally restore the preference snapshot after quitting every instance:

```sh
# Replace the example with the exact backup you selected; retain the quotes.
defaults import org.redstonedesktop.RedstoneDesktop "/absolute/path/to/your/backup/preferences.plist"
```

Preference restoration restores remembered script approvals/pack selection too. Forget approvals in Settings if you do not want them restored. The usual exact-file/contents checks still apply. No command here changes macOS privacy permissions.

Do not run multiple independent app copies against the same save directory during reset/recovery. Backups have no automatic expiration and consume disk space; delete old backups manually only after verifying a newer export/backup.

## Contributor checks

XCTest fixtures use temporary directories, isolated preference suites, fake Finder/opener/script adapters and silent/offline audio. The test host never loads the owner's store. After a Debug build, `scripts/maintenance-smoke.sh` uses public relaunch with paired Debug-only `REDSTONE_DESKTOP_DATA_ROOT` / `REDSTONE_DESKTOP_PREFERENCES_SUITE` settings and a temporary store. It checks a distinct native app PID, actual Setup appearance, empty/stopped state, no Finder read and no old shutdown write. The isolated child quits automatically; the harness cleans its own temporary data. These environment settings are developer-only, not a production data-location feature.

The terrain-upgrade regression suite covers source-byte backups, one-time upgrades, painted-ground protection, old exports, strict damaged-save rejection, mouse-release terrain saving and desktop assignment. A rehearsal against a temporary copy of the owner’s saved library preserved all three worlds, four areas, circuit settings and lever states while adding five support overrides; both operations then persisted successfully. The rehearsal did not write to the owner’s active library. Physical-Mac acceptance remains in [TESTING.md](TESTING.md).
