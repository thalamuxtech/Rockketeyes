# Third-Party Asset Licenses

All bundled third-party assets are either **CC0 1.0 (public domain dedication)** or the **SIL Open Font License 1.1**. All are safe for commercial use. Licenses were checked on each asset's source page when it was downloaded (2026-09-25).

- CC0 1.0: https://creativecommons.org/publicdomain/zero/1.0/
- SIL OFL 1.1: https://openfontlicense.org/ (full text is bundled next to each font)

CC0 does not require attribution. We credit the authors anyway, as good practice and because several of them asked for it.

## Fonts (`assets/fonts/`)

| File | Original title | Author | Source | License | Modifications |
|---|---|---|---|---|---|
| `Sora-Variable.ttf` | Sora[wght].ttf | The Sora Project Authors (sora-xor) | https://github.com/google/fonts/tree/main/ofl/sora | [SIL OFL 1.1](https://openfontlicense.org/). Text in `Sora-OFL.txt` | Renamed only |
| `Inter-Variable.ttf` | Inter[opsz,wght].ttf (upright) | The Inter Project Authors (rsms) | https://github.com/google/fonts/tree/main/ofl/inter | [SIL OFL 1.1](https://openfontlicense.org/). Text in `Inter-OFL.txt` | Renamed only |
| `Sora-OFL.txt` | OFL.txt | — | https://github.com/google/fonts/blob/main/ofl/sora/OFL.txt | — | Renamed only |
| `Inter-OFL.txt` | OFL.txt | — | https://github.com/google/fonts/blob/main/ofl/inter/OFL.txt | — | Renamed only |

Under the OFL, the fonts may be bundled and embedded in commercial software. The license text must stay with them, and they must not be sold on their own.

## Music (`assets/audio/music/`)

| File | Original title | Author | Source page | License | Modifications |
|---|---|---|---|---|---|
| `menu_ambient.mp3` | Calm Ambient 1 (Synthwave 4k) (`001_Synthwave_4k_0.mp3`) | The Cynic Project / cynicmusic (Alex) | https://opengameart.org/content/calm-ambient-1-synthwave-4k | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) | Trimmed from 2:38 to 2:20. 1.5 s fade in and out. Two-pass loudness normalization to -20 LUFS. Re-encoded to MP3 128 kbps, stereo, 44.1 kHz. |
| `play_focus_1.mp3` | November Snow (`155 November_snow-33_tape_leveled.mp3`) | The Cynic Project / cynicmusic | https://opengameart.org/content/november-snow | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) | Trimmed from 5:50 to the first 2:20. 1.5 s fade in and out. Normalized to -20 LUFS. Re-encoded to MP3 128 kbps, stereo, 44.1 kHz. |
| `play_focus_2.mp3` | Chill lofi inspired [loop edit] (`chilllofir-loop.ogg`) | omfgdude (original), qubodup (loop edit) | https://opengameart.org/content/chill-lofi-inspired-loop-edit (original: https://opengameart.org/content/chill-lofi-inspired) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/). Both the original and the loop edit are CC0. | Full length (1:37). 1.5 s fade in and out. Normalized to -20 LUFS. Converted from OGG to MP3 128 kbps, stereo, 44.1 kHz. |

## Sound effects (`assets/audio/sfx/`)

Every SFX went through the same steps: leading silence removed (`silenceremove`, -50 dBFS threshold) so it plays instantly, trailing silence removed, a 2 ms anti-click fade in and a short fade out, gain set to about -18 LUFS (measured the loudnorm way), a peak limiter, and encoding to MP3 128 kbps, mono, 44.1 kHz.

| File | Original title | Author | Source page | License | Modifications (besides the common steps) |
|---|---|---|---|---|---|
| `correct.mp3` | `confirmation_001.ogg` from the "Interface Sounds" pack | Kenney (Kenney Vleugels) | https://kenney.nl/assets/interface-sounds | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/). Stated on the page and in the pack's License.txt. | — |
| `wrong.mp3` | `error_005.ogg` from "Interface Sounds" | Kenney | https://kenney.nl/assets/interface-sounds | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) | — |
| `tick.mp3` | `tick_004.ogg` from "Interface Sounds" | Kenney | https://kenney.nl/assets/interface-sounds | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) | — |
| `tap.mp3` | `drop_002.ogg` from "Interface Sounds" | Kenney | https://kenney.nl/assets/interface-sounds | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) | — |
| `go.mp3` | sfx_start_generic_lessreverb.wav | Mihacappy (Freesound) | https://freesound.org/people/Mihacappy/sounds/844143/ | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) | Taken from the Freesound HQ MP3 preview |
| `finish.mp3` | GASP_Chimes_Success_4.wav | Rob_Marion (Freesound) | https://freesound.org/people/Rob_Marion/sounds/541985/ | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) | Taken from the Freesound HQ MP3 preview. Quiet reverb tail trimmed (1.59 s to 1.27 s). |
| `whoosh.mp3` | Little Whoosh 3 | ch_ase (Freesound) | https://freesound.org/people/ch_ase/sounds/423798/ | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/) | Taken from the Freesound HQ MP3 preview. About 0.5 s of leading silence and the quiet tail removed (2.47 s to 1.57 s). Gain raised by about 25 dB because the source is very quiet. |

## Credits

Music by The Cynic Project (cynicmusic.com), omfgdude and qubodup, via OpenGameArt.org. Sound effects by Kenney (kenney.nl), Mihacappy, Rob_Marion and ch_ase, via Freesound.org. Fonts: Sora by the Sora Project Authors, Inter by the Inter Project Authors.
