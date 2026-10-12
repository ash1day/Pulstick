# Pulstick

A minimal metronome that lives in your macOS menu bar.

**https://ash1day.github.io/Pulstick/**

## Features

- Tempo 30–300 BPM: drag, use the ± buttons or arrow keys, tap along, or click the number and type
- Up to 16 beats per bar with any beats accented, plus four presets you can overwrite (right-click)
- Songs: save the tempo, beat pattern and subdivision under a song name and recall it in one click
- Subdivisions: eighths, triplets, sixteenths
- Three click sounds (beep, wood, tick), all synthesized in code
- Mute: click the speaker to silence the click while the beat display (and the menu bar beat number) keeps going
- Speed trainer: raise the tempo by N BPM every M bars up to a target
- Silent bars: play N bars, then mute M bars to check you hold the tempo yourself
- Menu bar shows the BPM while playing; the Play button shows practice time
- Practice timer: right-click Play to stop automatically after 5–60 minutes
- Practice log: minutes practised today, your streak of consecutive days and a 7-day chart
- Global shortcuts: <kbd>⌃⌥M</kbd> play/stop, <kbd>⌃⌥T</kbd> tap tempo
- Settings are remembered between launches
- English and Japanese UI (follows the system language)

## Build

```bash
./build.sh
```

Requires Xcode (the SwiftUI macros are not in the Command Line Tools alone). `build.sh` uses Xcode automatically when `xcode-select` points at the CLT.

## Development

```bash
./dev.sh                     # rebuild and relaunch the app
swift test                   # unit tests (silent: they never play audio)
.build/debug/Pulstick --snapshot out.png [--dark] [--beats N] [--trainer] [--gap] [--log] [--songs] [--muted] [--shortcuts] [--timer]
                             # render the popover to a PNG without launching the app
```

## License

MIT
