# Middy

**Power on. Patch in. Roll the dice.**

Middy is a live MIDI sequencer for macOS with a glowing CRT and a soft spot for acid bass. It writes eight parts in 4/4 as it plays, locked to Ableton Live over Link. Watch the notes scroll by, ride the drop, or hit the dice for a fresh arrangement.

![Middy’s CRT showing lead, plucks, pads, drums, and bass during a verse](docs/images/middy-crt.png)

[Build Middy](#build-and-open) · [Grab the Live Set](ableton/Middy.als) · [Connect to Live](#connect-to-live)

## Build and open

Requires macOS 14 or newer, the Xcode command-line tools with Swift 6, CMake, and Git. The first build fetches Ableton Link 4.1.1 and its pinned Asio dependency.

```sh
./scripts/build
open .build/Middy.app
swift test
```

## Included Ableton Live Set

Open [Middy.als](ableton/Middy.als) in Live after launching Middy, then enable **Link** and the **Middy** MIDI input. The set already assigns the eight MIDI channels. The Plucks and Sub Bass tracks use **All Ins** on channels 7 and 5. Set them to **Middy** if you want to isolate those tracks from other controllers.

The set was saved in Live 12.4.16 Suite. It references the **Build and Drop** and **Stray Cats Collection by Max for Cats** Packs, a **Serum 2** factory ride sample, and **Kickstart 2** (VST). Have those installed or swap the missing sounds and plug-ins for your own.

## Connect to Live

1. Enable **Link** in Live. Allow Middy to access the local network if macOS prompts you.
2. In Live's **Link, Tempo & MIDI** settings, enable **Track** for the **Middy** MIDI input.
3. Add up to eight MIDI tracks. Set **MIDI From** to **Middy**, choose the channel below, and set monitoring to **In** for playback.
4. Open Middy once the tracks are routed. Set Live's Global Quantization to **1 Bar** for matching four-beat launch boundaries.

| MIDI channel | Part | Set up in Live |
| --- | --- | --- |
| 1 | Lead | Load a lead synth |
| 2 | Bass | Load an acid bass synth |
| 3 | Drums | Load a Drum Rack with the pads below |
| 4 | Pad | Load a polyphonic synth |
| 5 | Sub bass | Load a sub synth |
| 6 | Environmental drone | Load a slow, sustained polyphonic instrument |
| 7 | Plucks | Load a bright synth for short octave-up lead accents |
| 8 | Formants | Load the robot-formant instrument |

Set the Drum Rack’s **Receive** notes to match these pads.

| Sound | Live note | MIDI note |
| --- | --- | ---: |
| Kick | C1 | 36 |
| Clap | D♯1 | 39 |
| Snare | D1 | 38 |
| Closed hat | F♯1 | 42 |
| Cymbal | C♯2 | 49 |
| Tambourine | F♯2 | 54 |
| Shaker | A♯4 | 82 |

## How Middy composes

- **Pick the material.** Each song gets a minor-key chord progression and two four-note motifs. The lead repeats and transposes those motifs, adding rests and varying note lengths.
- **Set the groove.** A bar accent pattern shapes the lead and sparse acid bass. Each song emphasizes either kicks or offbeats, with drums, pads, and accents entering and dropping out.
- **Arrange the song.** Intro → build → verse → breakdown → build → verse → outro. The outro previews the next song in a closely related minor key.

The desktop Ableton Link library is available under [GPLv2+ or a proprietary license](https://github.com/Ableton/link/tree/Link-4.1.1#license).
