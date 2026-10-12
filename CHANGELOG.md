# Changelog

## Unreleased

### Practice
- **Speed trainer**: raise the tempo by N BPM every M bars up to a target, with a one-click return to the starting tempo and an optional repeat mode.
- **Silent bars**: play N bars, then mute M bars while the beat display keeps going, to check you hold the tempo on your own.
- **Subdivisions**: eighths, triplets and sixteenths with a softer click.
- **Rest beats**: click a beat to cycle normal → accent → rest, e.g. a click only on 2 and 4.
- **Songs**: save tempo, beat pattern and subdivision under a name, keep them in setlist order, step through them with `[` and `]` (Pulstick remembers where you were), and see how long you have practised each one and the fastest tempo you reached. The current song's name appears under the BPM.
- **Practice log**: today's minutes, your streak of days and a 7-day chart. Right-click it to reset the history.
- **Practice timer**: right-click Play to stop after 5–60 minutes.
- **Mute**: silence the click and follow the beat display (the menu bar shows the beat number).

### Tempo and sound
- Tempo range is now 30–300 BPM, with the Italian tempo marking shown next to the BPM.
- Click the BPM to type a tempo.
- Tap tempo uses the median of the last few taps, so one late tap does not throw it off.
- Three click sounds: beep, woodblock and tick.
- The click keeps going while you drag the tempo slider.
- Audio restarts by itself when the output device changes (for example, plugging in headphones).

### Everyday use
- Your settings are remembered between launches.
- While playing, the menu bar shows the BPM.
- Global shortcuts: ⌃⌥M play/stop and ⌃⌥T tap tempo, from any app. A keyboard button lists all shortcuts.
- A one-time welcome on first launch shows where Pulstick lives.
- Japanese localization, VoiceOver support, and Reduce Motion / Increase Contrast support.
- New app icon.

### Fixes
- The volume sliders only produced 0 % or 100 %.
- A possible crash when changing the beat pattern while playing (data race).
- After a quick stop and start, a beat from the previous run could appear.
- A click could sound once after stopping.

### Distribution
- Releases are built for both Apple Silicon and Intel, ad-hoc signed and attached as `Pulstick.zip` by GitHub Actions.

## 1.0

- First release: menu bar metronome with tap tempo, accent beats, presets and Launch at Login.
