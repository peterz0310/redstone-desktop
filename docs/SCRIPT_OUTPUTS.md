# Script Output actions — Slices 29/29A/29B

Outputs use the app’s **Default** behavior, initially **Open occupant**, including components decoded from older saves. To opt in, stop the active desktop, choose Move, select an Output and change **Output action → Execute script** in the Inspector. **None** disables its file action while preserving its simulation/visual activation. Tools place ordinary Default outputs; no imported pack can configure an action. Editing an inactive world never runs it.

## Supported targets and execution

A fresh Finder snapshot must identify exactly one local regular file on the visible active Output. Supported resolved extensions:

| Extension | Interpreter | Arguments |
| --- | --- | --- |
| `.sh`, `.command` | `/bin/sh` | `--`, absolute resolved file path |
| `.zsh` | `/bin/zsh` | `-f`, `--`, absolute resolved file path |

The interpreter comes from the resolved extension, not the shebang, Finder display name or resource pack. Python, app bundles, Finder aliases, folders, unknown item kinds, remote URLs and other executable types are refused. Files must be readable and at most 1 MiB. Execute permission is unnecessary because the interpreter reads the file. Filesystem symlinks resolve to their canonical target before preview/authorization; extension validation then applies to that target. A `.command` file requiring zsh should be named `.zsh` for this implementation.

The working directory is the resolved script's parent folder. Standard input is `/dev/null`; the process inherits the app's environment and runs as the current account. No terminal opens, no login shell is started, and there is no `-c` command string, filename interpolation, sudo or privilege elevation. `-f` prevents zsh startup files. Scripts execute their own contents normally; this feature is not a sandbox. Resource-pack loading/importing never executes any code.

## Authorization and fresh targeting

Each unapproved activation opens a dedicated SwiftUI confirmation window, even if the editor is closed. It previews the full resolved path/interpreter and offers Cancel or Run Script. **Remember my choice for this script** starts checked and remembers the canonical path, filesystem identity and SHA-256 contents fingerprint. Editing/replacing/retargeting the file asks again. Approvals persist separately in app preferences (`approvedScripts`), never in library JSON or packs; at most 256 approvals are retained. **Settings → Forget Script Approvals** revokes remembered permissions. There is no bypass setting in this slice.

After approval, acquire a fresh read through the existing shared Finder gate. Refuse missing, changed or ambiguous occupancy and revalidate the script identity/contents. An Output never falls back to its previous target. A world/area/runtime/display/layout change or Stop/Quit cancels the pending action; an old approval cannot launch into a new session or be remembered after cancellation. A held Output still produces only one rising activation. Turning an input off and on produces another activation; cancellation does not queue a retry. Explicit Start with a saved ON lever can produce a fresh activation, following the existing runtime contract.

The second check reduces file-change races; it does not lock the filesystem. The owner can still modify a file between validation and the interpreter opening it. Remembered permission authorizes the checked file, not a guarantee that an external process cannot alter it. Use scripts you control.

## Results and lifecycle

Execution uses documented Foundation [Process](https://developer.apple.com/documentation/foundation/process), with independently drained nonblocking stdout/stderr pipes. Retain at most 1 MiB per stream, continue draining excess and show truncation. MainActor remains free while waiting. On child exit, drain available data and close pipes; descendants retaining pipe descriptors cannot hang the action. A 30-second timeout or Stop/Quit sends termination to the launched process; if it is still running after two seconds, public POSIX SIGKILL targets that child only. Independently launched/detached descendants and a script's earlier side effects are not undone. This is a bounded utility runner, not a general process supervisor.

**Advanced → Desktop Details → Last script result** shows resolved path, stdout, stderr, exit code, duration and truncation for the last completed action. Nonzero exits remain visible results. Captured text is session-only and is not persisted or sent to OSLog; it may contain whatever the script prints. A cancelled old-session completion does not replace current results. Launch/read/timeout failures appear in the last action message. Since Slice 29B, accepted input waits through a short background Finder read and performs a fresh check; one input may wait behind an Output refresh and busy repeats coalesce. The input/action slot remains busy while authorizing/executing; later input clicks ask you to retry, with no deferred input after the script. Stop/layout/session changes discard waiting input. Outputs activate only on an off-to-on power transition; replacing an occupant while powered does not rerun the action. Existing bounded Output queue and visibility/occupancy guards remain.

## Saving and contributor boundaries

`CircuitComponent.outputAction` is an optional-on-decode Codable field with `openOccupant` as its missing-field default (the app’s Default routing mode since 29A); valid values are `openOccupant`, `executeOccupant`, `none`. Explicit null/unknown values fail validation. The library remains format 1; world format 5 includes sparse terrain edits and visual world lighting, with no Finder paths or approvals embedded. Simulator/renderers ignore the mode and never launch files; AppState dispatches rising edges to the action adapters.

- `ScriptTarget.swift`: target validation/resolution/fingerprint and Sendable result.
- `ScriptAuthorization.swift`: separate preference store and SwiftUI confirmation presenter.
- `ExecuteScriptAction.swift`: approval/revalidation transaction with injected executor, authorizer and freshness checks.
- `ScriptProcess.swift`: cancellable asynchronous execution and bounded capture.
- `ScriptExecutionTests.swift`: native harmless temporary scripts plus fake Finder/authorization/executor integration. Test startup never touches the owner's saved library/approvals or executes a real Desktop item.
- `examples/Scripts/hello.sh`: original MIT fixture printing stdout/stderr only; no file/settings mutation.

Fixed paths, arbitrary interpreter selection, developer bypass, terminal UI, advanced redstone and resource-pack code are outside this slice.

## Mac walkthrough

1. Quit the previous build with ⌘Q and reopen `build/Build/Products/Debug/RedstoneDesktop.app` (or Run in Xcode). Confirm ordinary desktop Finder items have no pink crosshairs. The tile hover and Output occupancy glow should still work.
2. In Finder open this repository's `examples/Scripts` folder. **Copy** `hello.sh` onto your Desktop (⌘C, click Desktop, ⌘V). It prints a greeting and example stderr without modifying files. Do not use an unfamiliar script for this check.
3. Stop Desktop. In the editor choose Move, select a visible existing Output and set **Output action → Execute script**. If using a repeater circuit, retain its direction/delay. Save Now, quit/reopen and confirm the selected Output retains this mode while Desktop starts stopped.
4. Move the copied `hello.sh` icon onto that Output on the physical desktop. Keep it away from the input. Start Desktop and click the circuit's button. The wire/repeater should activate before the confirmation appears. Check the preview points to your Desktop copy, then click **Cancel**: nothing runs.
5. Wait for power to turn off, then press again. Uncheck **Remember my choice for this script**, then click **Run Script**. Open **Advanced → Desktop Details**, expand **Last script result**, and check greeting stdout, example stderr, exit 0 and duration. Held power must not run it again. A later fresh activation should ask again.
6. Repeat with **Remember my choice for this script** enabled. Later activations of that unchanged file skip the prompt. Use **Settings → Forget Script Approvals** to restore prompting. Editing the file also requires fresh approval.
7. While a prompt is open, move the script off the Output and then approve: execution should be refused. A later press with an empty Output must not run the old script. Stop Desktop while a prompt is open: the prompt should close and no delayed execution should occur after Start. Keep the script away from inputs when checking normal Finder selection/drag.
8. Turn automatic routing off, then switch the Output back to Default (open occupant) and verify ordinary folder opening still works. New script MANUAL checks remain pending until owner confirmation; automated success is not physical Finder/permission/focus proof.


## Settings and early Desktop access

**Redstone Desktop → Settings… (⌘,)** or **Advanced → Settings…** opens native SwiftUI settings. **Run supported scripts; open other items** is an OFF-by-default opt-in stored under `scriptOutputSettings`, separately from library.json. Existing `openOccupant` modes serve as Default: they open normally while off; while on, a unique current local regular Finder file with case-insensitive `.sh`/`.command`/`.zsh` filename extension enters the same approval/execution transaction. Folders, apps, Finder aliases, documents and unsupported extensions use ordinary opening. This is routing, not blanket script authorization; fresh targeting, exact-file approval and resolved-file validation still apply. If a script-like candidate resolves to an unsupported/invalid target, refuse it rather than silently open it. Explicit Execute script remains script-only and None disables action. The Inspector names the effective default.

Turning the setting on/off cancels pending approval/action work and drops queued activations, while keeping power/cameras/worlds unchanged. It does not replay a held Output or execute anything merely from changing the preference. Restoring it on startup starts no integration or folder request.

Choosing Execute script in the Inspector or explicitly enabling automatic routing requests an early read-only Desktop-directory access attempt. `DesktopScriptAccess` gets the standard Desktop URL with FileManager, opens it and reads/discards one entry on a worker, then closes it; it never reads file contents, builds a filename list, writes files, queries Finder positions or runs a script. The app declares [NSDesktopFolderUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsdesktopfolderusagedescription). macOS controls prompting and prior decisions; this moves an actual access attempt earlier, rather than using a private permission API or pretending consent can be forced. A successful directory attempt is current access evidence, not a durable TCC status guarantee or a guarantee about every child process/linked target.

Access attempts are serialized and automatic opt-ins do not repeatedly retry a denied/failed attempt in the same session. Settings shows the result and **Check Desktop Access…** explicitly retries. Existing permission often means no prompt; a known denial may need **System Settings → Privacy & Security → Files & Folders**. Do not reset privacy permissions to force a test. Finder Automation, Desktop-folder consent and Run Script approval are separate. Tests inject this adapter or use temporary folders; test startup has no real Desktop checker.

The exact-script checkbox starts checked but **Cancel grants nothing**; uncheck it to approve only this activation. Edited/replaced files ask again. Revocation lives in Settings, linked from Desktop Details. Results remain in Desktop Details.

## Slice 29A settings and earlier permission walkthrough

1. Quit with ⌘Q and reopen the rebuilt app. Open **Redstone Desktop → Settings… (⌘,)** or **Advanced → Settings…**. Fresh settings leave automatic routing off; existing worlds remain intact and Desktop starts stopped.
2. With Desktop stopped, select an Output and choose Execute script. Check Settings for a Desktop-access result. If macOS needs first consent it should ask at this point; since you already allowed it, **no new prompt is expected**. **Check Desktop Access…** should report success; any failure should show a useful message. Do not reset macOS permissions just to make it ask again. If it still waits until circuit execution to request access, report the exact requesting app and dialog so we can verify attribution.
3. Set that Output to **Default**, then enable **Run supported scripts; open other items** in Settings. Put the harmless Desktop copy of `examples/Scripts/hello.sh` on it, Start Desktop, and press its circuit input. A new file should still show a resolved-path Run Script prompt with **Remember my choice for this script checked**. Approve, wait for power to go off, then press again: the unchanged approved file should run without another app confirmation.
4. Move the script away and place a harmless folder on that same Output. On a fresh input activation it should open the folder normally. None should open/execute nothing; explicit Execute script should refuse the folder. No mode chooses among ambiguous occupants.
5. Use **Settings → Forget Script Approvals**. Put the script back; at the next prompt uncheck remembering and run. The following fresh activation should ask again. Cancel should execute nothing. Turning automatic routing off while a prompt is open should dismiss it/refuse any stale approval without running or remembering that request.
6. Save/quit/reopen. Automatic routing should retain your preference, with Desktop stopped and no automatic action/access request. Check setting changes during held power do not activate again. If testing an unrecognized extension such as `.py`, expect ordinary opening; Python/interpreter selection is future scope. These new MANUAL checks await owner confirmation.

## Future first-launch setup and Start Over

The planned Slice 33 wizard will explain worlds/areas and request permissions when choosing the matching feature, with Skip and reopen Setup. It will not automatically enable Desktop or execute a script. Settings’ planned **Start Over…** will require confirmation, preserve a recoverable local backup of worlds/areas and the legacy migration source, stop all runtime/background work, reset app-owned library/settings/approvals/appearance/setup state, then close/relaunch into fresh setup. It must prevent old autosaves or legacy re-import from restoring cleared state. Failure preserves existing data with recovery guidance.

Desktop files, external source JARs/packs and other apps’ data are outside reset scope. macOS privacy choices remain intact; returning to app-first-launch state does not force system permission prompts. Wizard/reset/relaunch are documented future work and are not implemented in this build.


## Powered Output chaining (Slice 30A)

An Output's configured action never controls its simulated power. Empty/ambiguous occupants, None mode, declined/failed scripts and offscreen Outputs may still supply a correctly oriented adjacent repeater's rear. That repeater emits 15 after its delay and can power another Output. Each visible Output rising edge still uses its own current session/layout/policy and fresh Finder/unique-occupant/approval checks. Actions remain serialized and bounded; a downstream signal does not wait for an upstream script to finish, though its queued action waits for the shared action slot. Stop cancels/drops that queued work. No direct Output-to-dust/Output/torch broadcast is supported. See [circuit rules and the chain walkthrough](REDSTONE_RULES.md#chaining-outputs--slice-30a-mac-walkthrough).
