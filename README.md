# AULA Studio

A native macOS app for AULA keyboards whose official software only runs on Windows.

| | AULA F75 Pro | AULA S75 Pro (experimental) |
|---|---|---|
| Per-key colours | Live, from the app | Saved on the keyboard |
| Lighting effects | 8 live effects (reactive typing, ripple…) plus its 18 built-in effects saved on the keyboard | All 20 built-in effects, with brightness, speed, direction and colour |
| Music Rhythm (keys react to the Mac's sound) | Yes | — |
| Key remapping (main and Fn layers) | Keys, key combinations and media keys | Yes, including mouse, macro and disable |
| Macros stored on the keyboard | — | Up to 100 |
| Sleep timer | Yes (1–20 min) | Yes |
| Response time, Win/Alt+F4/Alt+Tab locks | — | Yes |
| Screen: GIF upload and clock sync | No screen | Yes |
| Profiles, import/export, undo/redo | Yes, separate per keyboard | Yes, separate per keyboard |

Neither keyboard has hall-effect switches, so there's no actuation point or rapid trigger to configure.

**S75 Pro support is experimental.** Its protocol comes from Aula's S75 Pro driver files and an open-source driver for the AULA EA75MAX, which has an identical configuration (same 80 keys, LED and remap slots, 135×240 screen and 141-frame limit). It's covered by the hardware-free self-checks but hasn't been run on a real S75 Pro yet. The app includes an S75 Pro simulator (App Settings) so you can try every feature without one.

## Install

1. Download `AULA-Studio-<version>.zip` from Releases and unzip it.
2. Move **AULA Studio** to Applications.
3. The app isn't notarized, so open it the first time with **right-click → Open → Open**.
4. When asked, allow **Input Monitoring** (System Settings → Privacy & Security). macOS protects keyboards behind this permission, and AULA Studio connects as soon as it's allowed.
5. Connect the keyboard with a USB cable in **wired mode**.

Music Rhythm also asks for **Screen & System Audio Recording** (to hear the Mac's sound; only audio is used) or **Microphone**.

## Using it

- Choose the keyboard at the top of the sidebar. Each keyboard keeps its own profiles.
- **F75 Pro:** effects run live from the app, so keep it running. It stays in the menu bar when the window is closed. "Keyboard's own lighting" hands control back to the keyboard.
- **S75 Pro:** edit, then press **Save to Keyboard** (⌘S). Only what changed is written.
- The S75 Pro's light bar has no software control in Aula's driver either. Set it on the keyboard with Fn + Shift (mode) and Fn + / (colour).

## Build from source

Requires macOS 13 or later and the Xcode command-line tools.

```bash
scripts/build-app.sh            # build/AULA Studio.app
swift run SelfCheck             # hardware-free protocol checks
scripts/package-release.sh      # universal build + zip for a release
```

Each local rebuild gets a new ad-hoc signature, so macOS asks for Input Monitoring again. Remove the old AULA Studio entry in Privacy & Security and allow the new one.

## How it works

**F75 Pro** (SinoWealth, USB `258a:010c`): HID feature report `0x06`, 520 bytes, on the vendor interface (usage page `0xFF00`), shaped `06 <command> <page> 00 01 00 <length>` + payload. A query (`06 82 01 00 01 00 06`) returns the model (`0xCD` = F75). Direct mode (`06 08 …` + RGB triplets by LED slot) must be refreshed at least every second. Onboard settings were decoded from a recording of AULA's own driver (made with `tools/hidlogger`, a logging stand-in for Windows' `hid.dll`): `84` reads the 128-byte settings block, `04` writes it back (effect, per-effect brightness 0–9 / speed 0–4 / colour slot, sleep in 30 s units), `0a` writes the 512-byte colour palette, and `03` writes the four 512-byte key pages (Default, FN1, FN2, Tap; one 4-byte entry per LED slot). Like AULA's driver, AULA Studio reads the settings block and changes only the bytes it understands; `swift run SelfCheck` rebuilds every recorded save byte for byte. The key layout comes from the config inside AULA's installer (`reference/device-cfg.ini`).

**S75 Pro** (SONiX, USB `0c45:800a`): 64-byte feature reports on usage page `0xFF13`, in transactions of begin `04 18`, a block command (lighting `04 13`, per-key `04 23`, remap `04 11` / `04 27`, settings `04 17`, macros `04 19`+`04 15`, clock `04 28`), data, apply `04 02`, and finalize `04 F0`. Screen images go as 4096-byte output reports on usage page `0xFF68` after `04 72`. The upload size is checked twice and can never pass the 141-frame limit, because the firmware writes the screen data straight to flash and data past the limit would overwrite its built-in graphics.

The project layout:

- `Sources/AulaCore`: protocol encoders, layouts, models, screen encoder (no UI, no IOKit)
- `Sources/AulaStudio`: the SwiftUI app, IOKit transport and audio analysis
- `Sources/SelfCheck`: protocol checks against the reference driver's test vectors
- `reference/` (not in the repository): config files extracted from AULA's installers. Only `tools/gen_layout.py` reads them; its output, `Sources/AulaCore/Layouts.swift`, is included. To regenerate it, unpack AULA's F75 installer (its `[KEY]` config as `reference/device-cfg.ini`) and S75 Pro installer (its keyboard XML as `reference/s75-pro/device.xml`)
- `tools/gen_layout.py`: regenerates `Layouts.swift` from `reference/`
- `docs/F75-CAPTURE-GUIDE.md`: how the F75 Pro's onboard commands were recorded and decoded

## Credits

- OpenRGB's `SinowealthKeyboard10c` work documented the F75 Pro's direct lighting.
- [thibaultmiclo/aula-driver](https://github.com/thibaultmiclo/aula-driver) (MIT) documented the EA75MAX protocol used for the S75 Pro. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
- The layout is inspired by Wootility. AULA Studio is not affiliated with AULA, Epomaker or Wooting.

## License

MIT. See [LICENSE](LICENSE).
