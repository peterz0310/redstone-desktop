# Redstone Desktop circuit rules

This is a deterministic 2D simulation, separate from SpriteKit, Finder and file/script actions. These rules describe the implemented app through Slice 30A. They do not promise Minecraft update-order parity. Packs supply validated pixels/audio, never logic. There is no vertical wiring, attachment/support-block simulation, burnout, quasi-connectivity or full powered-block conduction.

## Ports and timing

North is positive world Y. A component's direction points forward; rear is its opposite. Only cardinal neighbors connect. Signal strength is 0–15.

| Component | Input | Output | Timing |
| --- | --- | --- | --- |
| Button | Accepted desktop click | 15 on every side | Next simulation tick; 20 powered snapshots; repeat presses extend the pulse |
| Lever | Accepted desktop click toggles state | 15 on every side while on | Next simulation tick; saved lever position |
| Dust | Adjacent emitting sources/dust | Current strength minus one to neighboring dust; current strength to a repeater rear or Output | Settles within the same tick |
| Repeater | Rear only, positive signal | 15 to front only | Both edges delayed 2/4/6/8 simulation ticks (1–4 redstone ticks) |
| Torch | Rear only, positive signal inhibits it | 15 to front and both sides while rear is off; never to rear | Both inversion edges delayed 2 simulation ticks (1 redstone tick) |
| Output | Any adjacent emitting port | Current positive strength to an adjacent repeater rear only | One action event on an off-to-on edge; repeater applies its own delay |

Simulation runs at 20 Hz (50 ms per tick); one redstone tick is 100 ms. Every delayed component matures its old history first, then the bounded dust solver runs. Outputs read the completed network and emit rising edges. All torch/repeater rear inputs sample that same completed snapshot to append history for future ticks. Dictionary insertion order cannot change the result. There is no recursive propagation.

A newly started torch's two history entries are ON. It emits at tick 1. If rear power is first sampled at tick 1, it switches off at tick 3. Rear power disappearing at tick T switches it on at T+2. Feedback can oscillate deterministically; histories and propagation remain bounded. Stop clears runtime power/history. Direction is saved in the existing component configuration; old worlds without torches retain their decoding defaults. Older app versions cannot understand the new torch kind; keep a backup before opening a torch world with older builds.

## Building a NOT circuit

Choose a clear grass/dirt/sand strip to the right of your existing circuits, with no decorations. An example on the starter construction patch is:

```text
(16,9)     (17,9)       (18,9)    (19,9)       (20,9)    (21,9)
Lever  ->  Torch →  ->  Dust  ->  Repeater → -> Dust  ->  Output
```

Set Torch and Repeater direction to **East**. The torch's rear is the lever at its west. Its arrow describes orientation; both sides also emit, so keep side wiring separate unless you intend that connection. The repeater's delay adds to the torch's fixed delay.

With the lever OFF, the torch is ON and powers the downstream circuit. Turning the lever ON extinguishes it after 100 ms; downstream power then clears after the repeater's delay. Turning the lever OFF restores power and creates another Output rising edge. Adjacent sources can feed a wire independently of the torch; avoid parallel connections that bypass the inverter when testing.

In the editor, choose Torch and a Direction, then click a valid empty tile. Navigate/select an existing torch, change Direction and click **Apply torch direction**. Erase works as for other components. In Desktop Build Mode, Torch is hotbar shortcut **7** (existing 1–6 unchanged); hover a torch and press **R**, or select it and use **Rotate Selected**. T/Delay only applies to repeaters; torches always use one redstone tick. Build Mode stops simulation until you explicitly Start Desktop again.

## Actions and startup

A torch is a power source even without a click. **Starting Desktop with an unpowered torch rear can immediately produce an Output rising edge.** First test with no file on the Output or configure its action as None. Add a harmless folder for action testing afterward. Script actions still require the separate authorization rules in [SCRIPT_OUTPUTS.md](SCRIPT_OUTPUTS.md).

Held power never repeatedly runs an Output. Moving/changing its occupant does not retrigger it. Wait for power to turn off, then create a new rising edge; the separate action adapter refreshes Finder before resolving the current occupant. Empty, ambiguous and unavailable occupants do nothing. Turning appearance/audio on or off does not mutate circuit logic.

Outputs supply only a correctly oriented repeater rear. They never directly power neighboring dust/Outputs or inhibit a torch rear. The Output signal is its strongest supported incoming level; this model merges dust's attenuated “weak” power and valid button/lever/repeater/torch “strong” power into that single level. There are no separate strong/weak flags. File occupancy, action mode/approval/result and visibility do not change that signal. Any positive rear input becomes 15 at the repeater front after its configured delay.

Each solve starts fresh from sources and matured delay history. An open chain clears after the source turns off and delays expire. Intentionally closed repeater/torch feedback may sustain or oscillate, but never runs a recursive or unbounded update. Stop clears runtime history. File actions have separate serialized Finder/approval/process latency; a signal arriving downstream does not guarantee the earlier script has finished.

## Owner Mac walkthrough

1. Run the updated app with **⌘R** in Xcode. Stop Desktop before editing.
2. Build the example above in a clear strip (use other coordinates if occupied). Leave the Output empty initially. Save/update and activate an area that includes the new circuit, then Start Desktop.
3. With the lever OFF, check the torch is bright red and the downstream wire/repeater are powered. Toggle the lever ON: torch and downstream power should go off shortly. Toggle OFF: they should return.
4. Put a harmless folder on the Output. Toggle ON, wait until the path is off, then toggle OFF. The folder should open once. Leaving power held must not reopen it.
5. Stop Desktop. Select the torch in Navigate mode, change direction and Apply. Verify the rear moves accordingly; restore East. Enter Desktop Build Mode, hover it and press R, and verify T does not change its fixed delay. Erase/re-place if desired; Exit, then explicitly Start.
6. Quit/reopen: torch placement/direction should survive, Desktop should start stopped. Existing button/lever/repeater circuits should work as before.
7. Optional: use built-in artwork, then Re-import a local Java version to get torch textures. Older generated packs fall back to the original torch artwork until re-imported. Toggle mute/effects and verify logic remains identical.

Physical Finder interaction, rendered appearance and these owner checks remain manual acceptance work. Automated tests cover ports, both-edge timing, propagation, feedback, persistence, editing, renderer connections, sound transitions and synthetic Java imports.


## Chaining Outputs — Slice 30A Mac walkthrough

1. Run the updated app with **⌘R** and Stop Desktop before building. Choose a clear grass/dirt/sand strip **to the right** of existing circuits. Keep it separated from neighboring wires/sources.
2. Place a Lever, then two Dust tiles, then Output A, a Repeater and Output B, in one straight row. Set the repeater to **East** for a left-to-right chain. Choose **4 redstone ticks** for an easy-to-see 400 ms signal delay. For example, use six clear tiles for `Lever → Dust → Dust → A → Repeater → B`; move the example if any terrain/decoration prevents placement.
3. Leave both Outputs empty or set A to None for the initial signal test. Save/update and activate an area containing the complete chain, then Start Desktop. Keep the lever and its neighboring tiles clear of Finder icons.
4. Click the lever ON once: A should power first; the repeater and B follow after 400 ms. A being empty or set to None must not block B's signal. Leaving it ON must not repeatedly activate either Output.
5. Click the lever OFF. A should turn off first; the repeater and B turn off after 400 ms. Stop Desktop, rotate the repeater sideways and Start again: A may power, but that repeater/B must not pick up its signal. Stop, restore East, and Start to continue.
6. Put distinct harmless folders on A and B (with action Default/Open); toggle OFF, wait until the whole chain is off, then ON. Each should open once. Signal/flash order is A then B; actual file actions also wait for fresh Finder reads and may take longer than 400 ms.
7. Replace B's occupant, then create another OFF→ON transition. The current replacement must open; changing it while power is held must not retrigger either Output. Repeat with A empty/None to confirm B can still open independently.
8. Stop while a refresh/action is pending: nothing queued should open afterward. Quit/reopen and confirm placements/delay persist, Desktop starts stopped and existing circuits work.

The renderer draws repeater connections only at its front and rear. Adjacent Outputs/dust do not gain direct broadcast power from this feature. No demonstration circuit is automatically added to existing saved worlds. Manual acceptance of these physical Mac checks remains pending.
