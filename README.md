# Middy

Middy is a standalone macOS MIDI sequencer for 4/4. It starts on the next Ableton Link bar when opened and releases held notes on quit. It starts in C minor with the pad enabled and zero octave offsets. Each new song moves to a neighboring minor key that shares six scale tones with the outgoing key. The full-window CRT shows the current key, phrase, bar count, and each track’s MIDI channel. Blue, green, white, and yellow traces show MIDI pitch by height, note duration by horizontal length, and velocity by thickness. Occasional drum fills glow muted red. The dice rolls a new seed for the entire arrangement at the next Link bar.

The conductor moves through Intro → Build (A) → Verse (B) → Breakdown (C/D/E) → Build (A) → Verse (B) → Outro. Verses last 24 bars, the breakdown lasts 64, and builds and transitions last 4. Eight-bar changes shape the supporting parts while the lead and bass patterns continue. Verse hats open up in the middle eight bars, then thin alongside the Plucks. Each song gives Plucks a role on the beat, on the upbeat, or on syncopated sixteenths. Each role shapes a repeating four-bar rhythm with an opening accent, a bar of rest, and a late ending accent. Plucks double higher or more stressed lead notes within those rhythmic slots and leave out the extra accents in the last eight bars of each verse. Selected pads shift at the eight-bar boundaries. The breakdown cycles through eight eight-bar phrases, revisiting three melodic and harmonic variations. The opening drone gives way to soft percussion, with later blocks leaving space in the drums and pads. When present, breakdown hats keep the same two offbeats per bar, then play all four offbeats for the final four bars. The outro doubles as the next song’s intro. Both transitions preview the incoming song’s lead motif at gentle velocity and play short excerpts from its verse harmony.

Each song changes its minor-key harmonic plan, chord voicing, and two motif contours. A, C, and E share one motif with their own pitch progressions, while B and D use the other motif. Motifs can step or leap a diatonic third. Verses and breakdowns repeat an eight-bar chord progression and melodic call and answer. A shared stress pattern shapes the bass rhythm and the lead and bass accents. Lead phrases leave rests between motif fragments and mix short passing notes with longer accents. The lead follows the same per-song kick or offbeat emphasis as the sub bass. The parts vary velocity and gate length, with subtle timing variation on melodic notes and percussion. Drum patterns repeat in four-bar phrases with section-specific cymbal entrances and fills. Shaker and tambourine appear only on selected build and verse bars. The kick stays on the beat. The main bass leaves space between attacks and occasionally plays a late-bar fifth or lower minor-seventh pickup. The sub bass follows every bass attack while staying on the root one octave below the main bass’s root. Each song picks kick or offbeat accents for the sub. Those notes are louder and ring longer. The optional pad plays gently staggered triads, quieter in breakdowns and stronger in returning verses. Some four-bar verse phrases shorten the pad chords to half or a quarter of their usual length. A song can leave either verse or the entire breakdown without pads. The last two bars of each build introduce the verse melody. Bass and sub bass enter together on the verse downbeat. Builds come in three intensities, and the two builds in a song use different intensities. Drum velocity and optional pad swells follow the build’s intensity. Gentle builds use a short fill, rising builds accelerate to sixteenths before a half-beat pre-drop, and peak builds reach thirty-seconds before a full-beat pre-drop. Both rolls leave a quiet pickup on the verse’s opening pitch. Formants give short two-note replies near phrase endings in selected verses, favoring verses without pads. The environmental drone holds three-note chords for four bars in transitions and the first eight bars of a breakdown. It occasionally enters the returning verse.

## Build and open

Requires macOS 14 or newer, the Xcode command-line tools with Swift 6, CMake, and Git. The first build fetches Ableton Link 4.1.1 and its pinned Asio dependency.

```sh
./scripts/build
open .build/Middy.app
swift test
```

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

The desktop Ableton Link library is available under [GPLv2+ or a proprietary license](https://github.com/Ableton/link/tree/Link-4.1.1#license).
