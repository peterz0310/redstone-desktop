# Reproducible local profiling

Run from the repository root:

```sh
scripts/pan-profile.sh                         # synthetic Java fixture; owner data untouched
scripts/polish-profile.sh                      # original-art pan/CPU/memory fixture + README GIF
scripts/maintenance-smoke.sh                   # after Debug build; isolated native reset/relaunch
```

The native Swift harnesses compile unoptimized with Swift 6 and use temporary/custom stores, no owner preferences, no Finder queries/actions and no speaker output. `pan-profile.sh` optionally accepts a local JAR path and uses a temporary cache; source art stays local. `polish-profile.sh` records 40 native SpriteKit frames in `docs/media/circuit-demo.gif`: 1152×384 pixels on the tested Retina Mac (576×192 logical-point viewport). It shows deterministic button/dust/repeater/Output power, not real Finder opening or a screen recording of the app.

Measured on 2026-10-08, Apple Silicon, macOS 27.0 (26A428), Xcode 27.0 (27A266a), Swift 6.4, XcodeGen 2.46.0:

| Isolated workload | Result |
| --- | --- |
| Original-art renderer, 160 pans | 174 ms total; worst step 5.32 ms |
| Terrain working set | at most 12 retained chunks |
| Peak RSS before/after pans | 42.25 / 50.83 MiB |
| Four seconds stopped idle | 0.013% process CPU (one full CPU = 100%) |
| 80 simulation ticks at 20 Hz after native snapshot generation | 1.55% process CPU |
| Whole harness peak including 40 GIF snapshots | 320.27 MiB |

`getrusage` measures process user+system CPU and **peak**, not current, RSS. Short CPU samples are noisy. Per-pan autorelease pools keep temporary native allocations from accumulating in this tight synthetic loop. The GIF capture's image/GPU allocation peak is reported separately and is not ordinary editor memory. Retained-chunk counts are bounded working-set evidence; these numbers are not proof against every memory leak.

This is an energy **CPU proxy**, not measured battery watts, Instruments Energy Log, or the complete live desktop/Finder/script/multi-display workload. Follow TESTING.md's Activity Monitor/extended pan/idle tests on your Mac, record model/OS/displays/pack, and compare sustained trends. Repeated growth or pauses need investigation with Instruments (Allocations/Time Profiler); do not label them fixed merely because this fixture passes.

Audio uses eight bounded voices, finite cached PCM, low default volume, mute/stop cleanup and a two-second idle stop. Offline tests exercise actual graph output/restart without speakers. Reduce Motion feedback uses a brief steady indicator and cleanup instead of fade; Build Mode retains its steady reduced-motion border.
