# Setup, export and recovery

First launch opens a four-page native setup window. **Next** explains worlds/areas, Finder Automation and optional scripts; **Skip Setup** and **Finish Setup** both remember completion. Open it again in **Redstone Desktop → Settings… → General → Open Setup…**. Setup never starts Desktop or runs a script. Existing installations also see it once after this update; their builds are retained.

Finder access is requested by **Connect to Finder…** or subsequent explicit tracking/Start. Script Desktop-folder access is requested separately by **Check Desktop Access for Scripts…**, selecting Execute, or enabling the routing setting. macOS controls actual prompt timing. Changed scripts still need per-file approval. Automatic routing remains off by default. No Accessibility, microphone, Full Disk Access or blanket permission is needed. See [script execution](SCRIPT_OUTPUTS.md).

## Export before experimenting

1. Stop Desktop and open **Settings → Data → Export Library…**.
2. Choose a location and save the JSON. This contains all worlds, seeds, terrain overrides, circuits, lever positions, named areas and desktop assignment.
3. Keep it somewhere outside the app's Application Support folder. It excludes Finder files/positions, scripts, permissions/approvals, imported texture contents and runtime power.

There is no in-app Import button yet. To restore an export: quit the app, preserve the current `library.json` elsewhere, then copy the export to `~/Library/Application Support/RedstoneDesktop/library.json` and reopen. A malformed/version-incompatible library is refused and writes are blocked; preserve both copies rather than overwriting a rejected library. Restoring always starts Desktop stopped.

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
