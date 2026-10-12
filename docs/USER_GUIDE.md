# Using Redstone Desktop

Redstone Desktop builds a world beneath your Finder files. Your files stay where they are; circuits can open them or run scripts you approve. Everything runs locally.

## Getting started

1. Drag Redstone Desktop from the DMG into Applications and open it.
2. Follow Setup. **Connect to Finder…** lets the app read desktop item names and positions. Textures, sounds and scripts are optional.
3. Place a **Button**, a connected path of **Dust**, and an **Output**. Start on clear ground, or paint Grass with the Terrain tool.
4. Use **Test Circuit** to try the wiring. Testing never opens files or runs scripts.
5. Save the view as an Area, choose **Activate on Desktop**, then **Start Desktop**. Put a folder on the Output and press the circuit’s button.

Keep Finder icons away from buttons and levers so a circuit press can be distinguished from selecting a file. The menu-bar logo lets you stop Desktop, switch its area or reopen the editor. Reopening the app starts Desktop stopped.

Reopen Setup in **Settings → General → Open Setup…**.

## Worlds and areas

A **World** keeps its terrain and circuits. An **Area** saves a view within that world. Areas in the same world share the same builds; different worlds are independent.

Use the cards beneath the editor to switch worlds or areas. Save a new view or update the current one. Right-click a card to rename or delete it. Browsing an area doesn’t change the running desktop until you activate it. Assigning a different area from the menu bar switches the running desktop to it.

**World Settings** controls a moving day/night cycle, a fixed time of day, or your Mac’s local time. A custom day can last from 2 minutes to 24 hours.

## Editing

- **Move:** drag to pan; click a component to inspect it. Scroll or pinch to zoom. The home button returns to the desktop area.
- **Select:** drag around a group. Copy, paste and undo work when the map has keyboard focus.
- **Terrain:** paint ground or decorations. Restore generated terrain to remove your edits.
- **Build:** pick a component and click to place it. Drag Dust to draw a wire. Erase removes components.
- **Inspector:** change the selected component’s settings. Most changes save automatically; sensor filters use **Save**. Hover a repeater and press **R** to rotate it or **T** to change its delay.
- **Blueprints:** browse ready-made circuits, place one, or save a selection for reuse. Example Outputs start with **Do nothing**; choose an action when you’re ready.

Right-click for relevant actions such as delete, rotate or changing a sensor’s detection source. Tools explain themselves on hover and beneath the selected tool.

**Build on Desktop** edits directly beneath your files with the circuit stopped. Exit Build Mode, then Start Desktop to run it.

## Circuit basics

Buttons give a short pulse; levers hold power until switched off. Dust carries power through connected paths, weakening with distance. Repeaters restore full strength after their chosen delay and send it forward only. A redstone torch inverts its rear input. A Lamp lights when powered; a regular Torch provides light without powering a circuit.

An Output acts when its power turns on. Holding it powered does not repeat the action, and replacing its file while powered does not trigger it again. Turn the input off and back on for another activation. A repeater facing away from a powered Output can carry its signal to another circuit; Outputs don’t directly power adjacent dust.

### Pressure plates and file sensors

A wooden plate detects **Any item** on its tile. A stone plate detects an exact item name or one of several file extensions. Set the filter in Inspector, then press **Save** or Return. Changes stay as a draft until saved. Right-click the component for detection options.

For **File extension**, enter a comma-separated list such as `pdf, png, jpg`. Spaces around entries and leading dots are accepted, and matching ignores case. A file matching any listed extension activates the sensor; folders, apps and Finder aliases are excluded. Empty entries cannot be saved. **Item name** matches one full filename, including its extension; commas in that mode are part of the name.

Detection uses the Finder icon’s center. Any matching item keeps the plate powered. Finder updates can take a moment after moving an icon. In Test Circuit, click a plate or sensor to simulate detection.

Starting Desktop with an item already on a detector can activate its connected Outputs. Start with their action set to **Do nothing** while experimenting.

### Output actions and scripts

Outputs open the current file or folder by default. **Do nothing** keeps the signal without opening anything. **Execute script** runs a supported script after approval.

In **Settings → Outputs**, enable **Run supported scripts; open other items** if you want Default Outputs to route script files to execution and other items to ordinary opening. This is off by default and does not bypass script approval.

Supported scripts are local, readable files no larger than 1 MiB: `.sh` and `.command` use `/bin/sh`; `.zsh` uses `/bin/zsh -f`. The resolved extension selects the interpreter, rather than the shebang. Scripts run as your account, from their containing folder, without a terminal. Only run scripts you trust.

The confirmation shows the resolved path. **Remember my choice for this script** starts checked; editing or replacing the file asks again. **Settings → Outputs → Forget Script Approvals** restores prompting. **Advanced → Desktop Details → Last script result** shows output, errors and exit status. Scripts have a 30-second timeout. Stop cancels pending work and terminates the launched script; it cannot undo earlier script effects or stop independently launched descendants.

Outputs need exactly one current item on the visible tile. Empty or overlapping items won’t be acted on. Files moved during approval are checked again before execution.

## Textures and sounds

The original look works without Minecraft. To use your own Java Edition assets, open **Settings → Appearance**, choose an installed Minecraft version and click **Use Minecraft Assets**. Setup offers this too. Both screens automatically check Minecraft’s usual macOS versions folder and select the newest detected version. **Refresh** checks again after installing or launching a version, while keeping your selection if it is still available. Installing the launcher alone may not download a version’s assets; launch that version first.

**Choose a Texture Pack or JAR…** accepts a local Java version JAR, Java pack ZIP, or unpacked pack folder. For another launcher location, choose its JAR manually. A folder needs `assets/minecraft/textures/` or supported sound paths. Bedrock packs, mods, shaders and custom models aren’t supported.

Supported terrain, circuit, particle and short sound assets are converted into a local cache. Installed-version sounds need the launcher’s asset cache. Missing assets use the original artwork or effects. Check **Import details** for skipped files. Water and lava can use their Java animations; other animated textures use their first frame. The app never downloads assets or executes game or pack code.

**More options & custom packs** accepts packs made specifically for Redstone Desktop. See the [pack format](RESOURCE_PACKS.md) to create one. Only one pack is active at a time. **Use Original Look** restores the built-in appearance.

Appearance settings control animations, scenery and particles independently. Your Mac’s Reduce Motion setting pauses animated effects. **Settings → Sound** controls effects and volume; World Settings controls daylight and local illumination.

## Permissions and troubleshooting

Finder access uses **System Settings → Privacy & Security → Automation → Redstone Desktop → Finder**. Script reading may also need **Files & Folders → Desktop Folder**. macOS controls when these prompts appear. Accessibility, Full Disk Access and microphone access aren’t required.

If a circuit doesn’t respond, check that Desktop is started and the intended area is assigned. Keep inputs clear of Finder icons and other app windows, check repeater direction, and wait for power to turn off before pressing again. **Settings → General → Finder Diagnostics** shows Finder connection information.

Changing displays, Spaces or desktop icon layout may need a moment for the app to settle. If an Output is empty, has multiple occupants or lacks a fresh Finder reading, it won’t launch an item. The Output’s glow is green for one item, red for empty, amber for overlapping items and gray for unavailable information.

## Saving and backups

Edits save automatically. **Settings → Data → Export Library…** saves all worlds, areas, terrain edits and circuits. **Import Library…** adds independent copies while preserving your current desktop assignment. Exports exclude Finder files, imported assets, settings and script approvals. The separate saved blueprint shelf isn’t included.

The whole library has a 2 MB limit. Edits that exceed it are refused without changing your build. Remove unused worlds or restore painted terrain to make room.

If a save fails, your work stays in memory. Quit offers **Stay Open**, **Retry Save**, or **Save Copy and Quit…**. Keep the recovery copy somewhere safe; don’t Force Quit with unsaved changes. Normal recovery copies can be imported like an export. Emergency copies may be larger than the normal library limit and need reducing before import.

### Start over and restore

**Settings → Data → Start Over…** backs up app data, resets settings and relaunches Setup. It does not delete desktop files, change source packs or reset macOS permissions. Export first if you also want a separate copy of your worlds.

**Reveal Backups Folder** opens the saved backups. They are kept until you delete them. To restore only the worlds from a backup:

1. Quit every copy of Redstone Desktop.
2. In Finder, choose **Go → Go to Folder…** and enter `~/Library/Application Support/RedstoneDesktop/`.
3. Move the current `library.json` somewhere safe, then **copy** the backup’s standalone `library.json` into that folder.
4. Reopen the app. Desktop starts stopped.

For a full data restore, preserve the active folder and copy the backup’s `Support` folder into Application Support, naming the copy `RedstoneDesktop`. Keep the backup intact. A remaining `reset-in-progress.json` means interrupted-reset recovery must finish before manually replacing data. This restores app data; settings and remembered approvals are stored separately in the backup’s `preferences.plist`.

## Building from source

For local development, install Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen), run `xcodegen generate` in the repository, then open `RedstoneDesktop.xcodeproj` and run the RedstoneDesktop scheme. Xcode is only needed to build or debug the source, not to use the downloaded app.
