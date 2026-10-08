# Redstone Desktop circuit rules

This is a deterministic 2D simulation, separate from SpriteKit, Finder and file/script actions. These rules describe the implemented app through Slice 30. They do not promise Minecraft update-order parity. Packs supply validated pixels/audio, never logic. There is no vertical wiring, attachment/support-block simulation, burnout, quasi-connectivity or powered-block relay yet.

## Ports and timing

North is positive world Y. A component's direction points forward; rear is its opposite. Only cardinal neighbors connect. Signal strength is 0–15.

| Component | Input | Output | Timing |
| --- | --- | --- | --- |
| Button | Accepted desktop click | 15 on every side | Next simulation tick; 20 powered snapshots; repeat presses extend the pulse |
| Lever | Accepted desktop click toggles state | 15 on every side while on | Next simulation tick; saved lever position |
| Dust | Adjacent emitting sources/dust | Current strength minus one to neighboring dust; current strength to a repeater rear or Output | Settles within the same tick |
| Repeater | Rear only, positive signal | 15 to front only | Both edges delayed 2/4/6/8 simulation ticks (1–4 redstone ticks) |
| Torch | Rear only, positive signal inhibits it | 15 to front and both sides while rear is off; never to rear | Both inversion edges delayed 2 simulation ticks (1 redstone tick) |
| Output | Any adjacent emitting port | None | One action event on an off-to-on edge |

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

Outputs remain terminal sinks. Repeater pickup from powered Outputs is planned for Slice 30A and is not implemented in this slice.

## Owner Mac walkthrough

1. Run the updated app with **⌘R** in Xcode. Stop Desktop before editing.
2. Build the example above in a clear strip (use other coordinates if occupied). Leave the Output empty initially. Save/update and activate an area that includes the new circuit, then Start Desktop.
3. With the lever OFF, check the torch is bright red and the downstream wire/repeater are powered. Toggle the lever ON: torch and downstream power should go off shortly. Toggle OFF: they should return.
4. Put a harmless folder on the Output. Toggle ON, wait until the path is off, then toggle OFF. The folder should open once. Leaving power held must not reopen it.
5. Stop Desktop. Select the torch in Navigate mode, change direction and Apply. Verify the rear moves accordingly; restore East. Enter Desktop Build Mode, hover it and press R, and verify T does not change its fixed delay. Erase/re-place if desired; Exit, then explicitly Start.
6. Quit/reopen: torch placement/direction should survive, Desktop should start stopped. Existing button/lever/repeater circuits should work as before.
7. Optional: use built-in artwork, then Re-import a local Java version to get torch textures. Older generated packs fall back to the original torch artwork until re-imported. Toggle mute/effects and verify logic remains identical.

Physical Finder interaction, rendered appearance and these owner checks remain manual acceptance work. Automated tests cover ports, both-edge timing, propagation, feedback, persistence, editing, renderer connections, sound transitions and synthetic Java imports.
