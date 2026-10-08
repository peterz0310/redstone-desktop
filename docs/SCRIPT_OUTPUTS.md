# Script Output actions — Slice 29

Outputs default to **Open occupant**, including components decoded from older saves. To opt in, stop the active desktop, choose Navigate, select an Output and change **Output action → Execute script** in the Inspector. **None** disables its file action while preserving its simulation/visual activation. Tools place ordinary Open outputs; no imported pack can configure an action. Editing an inactive world never runs it.

## Supported targets and execution

A fresh Finder snapshot must identify exactly one local regular file on the visible active Output. Supported resolved extensions:

| Extension | Interpreter | Arguments |
| --- | --- | --- |
| `.sh`, `.command` | `/bin/sh` | `--`, absolute resolved file path |
| `.zsh` | `/bin/zsh` | `-f`, `--`, absolute resolved file path |

The interpreter comes from the resolved extension, not the shebang, Finder display name or resource pack. Python, app bundles, Finder aliases, folders, unknown item kinds, remote URLs and other executable types are refused. Files must be readable and at most 1 MiB. Execute permission is unnecessary because the interpreter reads the file. Filesystem symlinks resolve to their canonical target before preview/authorization; extension validation then applies to that target. A `.command` file requiring zsh should be named `.zsh` for this implementation.

The working directory is the resolved script's parent folder. Standard input is `/dev/null`; the process inherits the app's environment and runs as the current account. No terminal opens, no login shell is started, and there is no `-c` command string, filename interpolation, sudo or privilege elevation. `-f` prevents zsh startup files. Scripts execute their own contents normally; this feature is not a sandbox. Resource-pack loading/importing never executes any code.

## Authorization and fresh targeting

Each unapproved activation opens a dedicated SwiftUI confirmation window, even if the editor is closed. It previews the full resolved path/interpreter and offers Cancel or Run Script. **Always allow this exact file** remembers the canonical path, filesystem identity and SHA-256 contents fingerprint. Editing/replacing/retargeting the file asks again. Approvals persist separately in app preferences (`approvedScripts`), never in library JSON or packs; at most 256 approvals are retained. **Advanced → Desktop Details → Forget Script Approvals** revokes remembered permissions. There is no bypass setting in this slice.

After approval, acquire a fresh read through the existing shared Finder gate. Refuse missing, changed or ambiguous occupancy and revalidate the script identity/contents. An Output never falls back to its previous target. A world/area/runtime/display/layout change or Stop/Quit cancels the pending action; an old approval cannot launch into a new session or be remembered after cancellation. A held Output still produces only one rising activation. Turning an input off and on produces another activation; cancellation does not queue a retry. Explicit Start with a saved ON lever can produce a fresh activation, following the existing runtime contract.

The second check reduces file-change races; it does not lock the filesystem. The owner can still modify a file between validation and the interpreter opening it. Remembered permission authorizes the checked file, not a guarantee that an external process cannot alter it. Use scripts you control.

## Results and lifecycle

Execution uses documented Foundation [Process](https://developer.apple.com/documentation/foundation/process), with independently drained nonblocking stdout/stderr pipes. Retain at most 1 MiB per stream, continue draining excess and show truncation. MainActor remains free while waiting. On child exit, drain available data and close pipes; descendants retaining pipe descriptors cannot hang the action. A 30-second timeout or Stop/Quit sends termination to the launched process; if it is still running after two seconds, public POSIX SIGKILL targets that child only. Independently launched/detached descendants and a script's earlier side effects are not undone. This is a bounded utility runner, not a general process supervisor.

**Advanced → Desktop Details → Last script result** shows resolved path, stdout, stderr, exit code, duration and truncation for the last completed action. Nonzero exits remain visible results. Captured text is session-only and is not persisted or sent to OSLog; it may contain whatever the script prints. A cancelled old-session completion does not replace current results. Launch/read/timeout failures appear in the last action message. The input/action slot remains busy while authorizing/executing; later input clicks ask you to retry. Existing bounded Output queue and visibility/occupancy guards remain.

## Saving and contributor boundaries

`CircuitComponent.outputAction` is an optional-on-decode Codable field with `openOccupant` as its missing-field default; valid values are `openOccupant`, `executeOccupant`, `none`. Explicit null/unknown values fail validation. The library remains format 1/world format 3, with no Finder paths or approvals embedded. Simulator/renderers ignore the mode and never launch files; AppState dispatches rising edges to the action adapters.

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
3. Stop Desktop. In the editor choose Navigate, select a visible existing Output and set **Output action → Execute script**. If using a repeater circuit, retain its direction/delay. Save Now, quit/reopen and confirm the selected Output retains this mode while Desktop starts stopped.
4. Move the copied `hello.sh` icon onto that Output on the physical desktop. Keep it away from the input. Start Desktop and click the circuit's button. The wire/repeater should activate before the confirmation appears. Check the preview points to your Desktop copy, then click **Cancel**: nothing runs.
5. Wait for power to turn off, then press again. Click **Run Script** without remembering. Open **Advanced → Desktop Details**, expand **Last script result**, and check greeting stdout, example stderr, exit 0 and duration. Held power must not run it again. A later fresh activation should ask again.
6. Repeat with **Always allow this exact file** enabled. Later activations of that unchanged file skip the prompt. Use **Forget Script Approvals** to restore prompting. Editing the file also requires fresh approval.
7. While a prompt is open, move the script off the Output and then approve: execution should be refused. A later press with an empty Output must not run the old script. Stop Desktop while a prompt is open: the prompt should close and no delayed execution should occur after Start. Keep the script away from inputs when checking normal Finder selection/drag.
8. Switch the Output back to Open occupant and verify ordinary folder opening still works. New script MANUAL checks remain pending until owner confirmation; automated success is not physical Finder/permission/focus proof.
