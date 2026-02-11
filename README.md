# Pulstick

A minimal metronome that lives in your macOS menu bar.

## Features

- **Menu bar resident** — one-click access, no Dock icon
- **BPM 40–240** — slider and +/- buttons
- **Tap tempo** — tap to set the tempo naturally
- **Time signatures** — 4/4, 3/4, 6/8, 9/8 presets
- **Custom accents** — tap beat dots to place accents on any beat
- **Keyboard shortcut** — Space to play/stop
- **Accurate timing** — high-priority background timer, independent of UI thread

## Requirements

- macOS 13 (Ventura) or later

## Build

```bash
./build.sh
```

This runs `swift build -c release` and creates `./build/Pulstick.app`.

## Development

```bash
# Kill running instance, rebuild, and relaunch
./dev.sh
```

## Install

1. Download `Pulstick.zip` from [Releases](https://github.com/ash1day/Pulstick/releases)
2. Move `Pulstick.app` to `/Applications`
3. First launch: right-click → "Open" → confirm (Gatekeeper bypass)

## Architecture

```
Sources/Pulstick/
├── PulstickApp.swift       # @main — MenuBarExtra entry point
├── PulstickView.swift      # Popover UI, custom slider, beat indicators
└── PulstickEngine.swift    # Audio engine, timer scheduling, tempo logic
```

- **Audio**: `AVAudioEngine` + `AVAudioPlayerNode` with programmatically generated sine wave clicks (no sound files)
- **Timing**: `DispatchSourceTimer` on a `.userInteractive` queue for jitter-resistant scheduling
- **UI**: SwiftUI `MenuBarExtra` with `.window` style popover

## License

MIT
