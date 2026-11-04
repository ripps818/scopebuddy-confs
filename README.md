# scopebuddy-confs

Config snippets for [ScopeBuddy](https://github.com/OpenGamingCollective/scopebuddy) (`scb`) that set up OptiScaler, FSR 4 and frame generation under Proton. Aimed at AMD RDNA3 on Linux.

## Install

```sh
./setup.sh
```

- Copies `*.conf` to `~/.config/scopebuddy/` and `lib/*.sh` to `~/.config/scopebuddy/lib/`.
- A changed existing conf is backed up as `<name>.conf.bak`.
- Moves old per-tool download folders into `~/.local/share/scopebuddy-dlls/` (`$SCB_DLLS`).
- Prints `MISSING:` for the AMD FSR 4.1.2 DLLs needed by `fsr412.conf` (not redistributed, so you add them yourself).
- Everything else downloads on first launch.

## How to use

Steam launch options stay:

```
scb -- %command%
```

`scb.conf` is sourced for every game. If `~/.config/scopebuddy/common.conf` exists, `scb.conf` sources it too (after the plugin reset, before its own settings). It is yours: not in this repo, so `setup.sh` never creates, overwrites, backs up or removes it. Put settings for every game there, for example `source "$SCB_CONFIGDIR/fsr-multi.conf"` or `export MANGOHUD_CONFIG=...`. The other confs are opt-in per game. Create `~/.config/scopebuddy/AppID/<appid>.conf`, put settings above the `source` line, then source the conf:

```sh
export PROTON_USE_OPTISCALER=nightly
FSR4_DLL_TARGET=rx7000
source "$SCB_CONFIGDIR/fsr-multi.conf"
```

Commenting out a `source` line removes what that conf installed. `lib/optiscaler-reset.sh` clears it at the start of each launch.

## `opti_config`

Defined in `scb.conf`. It is a shell function that adds OptiScaler settings to `PROTON_OPTISCALER_CONFIG`, which Proton-CachyOS turns into `OptiScaler.ini` values.

```sh
opti_config Section.Key=value [Section.Key=value ...]
```

Example, in a game's AppID conf:

```sh
opti_config FSR.UpscalerIndex=0 FSR.Fsr4GpuSupport=2
```

- Entries are joined with `;`. You can call it as many times as you like.
- For the same key, the later value wins.
- Each argument must look like `Section.Key=value`. The value can't contain `;` or `=`. Anything else is skipped with a warning on stderr.
- It exports `PROTON_OPTISCALER_CONFIG`.
- It only does something when Proton's OptiScaler is on (`PROTON_USE_OPTISCALER=1` or `nightly`).

## Confs

| Conf | What it does | Needs |
|---|---|---|
| `scb.conf` | Global defaults: defines `opti_config`, runs the plugin reset, sets MangoHud, auto resolution/HDR/VRR, gamescope `--fullscreen --mangoapp`. Sources `lib/optipatcher.sh` when OptiScaler is on. | Always sourced by ScopeBuddy |
| `noscope.conf` | Wayland (`PROTON_ENABLE_WAYLAND=1`) plus `scb.conf`. | — |
| `fsr4.conf` | Enables the low-latency layer and `PROTON_FSR4_UPGRADE`. Forces OptiScaler onto the INT8 FSR 4 model (`Fsr4GpuSupport=2`), since RDNA3 is otherwise detected as unsupported. | OptiScaler |
| `fsr412.conf` | Copies AMD's official FSR 4.1.2 DLLs into the prefix's OptiScaler folder. | `PROTON_USE_OPTISCALER=nightly`, DLLs in `$SCB_DLLS/fsr4-4.1.2/` |
| `fsr-multi.conf` | Installs extra upscalers as OptiScaler "custom" entries. `cyboman-*` are faster FSR 4.1.1/4.1.2 builds, exact or lossy. `hlx-fsr4` is HelixSR's FSR 4 DLL. `hlx-dlss` is HelixSR's DLSS network, once you have built it. Kept up to date automatically. | `PROTON_USE_OPTISCALER=nightly` |
| `cyboman.conf` | Faster FSR 4.1.1 INT8 shaders from `zgauthier2000/fsr4-shader-performance-overrides`. `override` mode uses vkd3d shader replacement. `dll` mode swaps the patched DLL into Proton's OptiScaler. `auto` picks one. | A clone of the repo in `$SCB_DLLS/cyboman-repo` for override mode. Not for RDNA4. |
| `mlfg.conf` | Forces FSR 4 (ML) frame generation instead of the FSR 3.1 fallback, with the RDNA3 FP8-to-FP16 workaround. Sets `FSR.FGIndex=0` under OptiScaler nightly. | Also needs `fsr4.conf` |
| `mfgunlocker.conf` | Installs MFG Unlocker as an OptiScaler plugin for XeMFG (up to 6x). | `PROTON_USE_OPTISCALER=nightly` (OptiScaler 10). Don't combine with `mlfg.conf`. |
| `opennr.conf` | Installs the OpenNR-OptiScaler fork (DLSS 5 neural rendering bridge, FSR-RR, XeFG) by overwriting Proton's OptiScaler in the prefix (nothing goes in the game folder). Sets `PROTON_USE_OPTISCALER=1` if it is unset. | Neural backend files in `$SCB_DLLS/opennr/backend/` |
| `venom.conf` | Installs [OptiScaler Venom](https://github.com/LorenzoKy/Optiscaler-Venom) (OptiScaler build with extra OSD rows / graphs and FG timing) by overwriting Proton's OptiScaler in the prefix (nothing goes in the game folder). `VENOM_CHANNEL=release` or `nightly`, or pin with `VENOM_TAG`. Turns on `LOW_LATENCY_LAYER`. A background loop waits for wine and overwrites Proton's OptiScaler. | `bsdtar` or `7z`, Python 3. Don't combine with `opennr.conf`. |
| `luma.conf` | Installs a [Luma Framework](https://github.com/Filoppi/Luma-Framework) HDR/rendering mod (ReShade addon) next to the game exe, picked per game with `LUMA_MOD=<name>` or guessed from the Steam folder name. Updates from the rolling `latest-N` release. | Python 3. With OptiScaler on, Luma's ReShade is loaded through OptiScaler (`Plugins.LoadReshade`) instead of as `dxgi.dll`. Don't combine with `opennr.conf`. |
| `llayer-fg.conf` | Swaps in a locally built Korthos low-latency layer with frame-gen pacing (PR #37). Use it instead of `LOW_LATENCY_LAYER=1`. | Build from `~/Projects/llayer-build/build.sh` |

Each conf has a header comment listing its settings (for example `FSR4_MODE`, `FSR4_DLL_TARGET`, `OPENNR_MODE`, `MFGUNLOCKER_TAG`). Those headers are the reference for the options.

Don't combine `fsr-multi.conf` with `cyboman.conf` in the same game.

## `lib/`

The confs are thin. Each one sources a script of the same name in `lib/`, and the script does the work.

| File | Role |
|---|---|
| `common.sh` | Shared helpers: `$SCB_DLLS`, `scb_guard_begin/end` (ScopeBuddy runs confs under `set -e`, so failures are guarded so they can't stop a launch), logging. |
| `optiscaler-reset.sh` | Removes the plugins and DLLs our confs installed, at the start of each launch. Skip it with `SCB_NO_RESET=1`. |
| `optipatcher.sh` | Updates OptiPatcher every 6 hours and installs it in the prefix. Skip it with `SCB_NO_OPTIPATCHER=1`. |
| `cyboman.sh`, `cyboman-release.sh` | Logic and release lookup for `cyboman.conf` and `fsr-multi.conf`. |
| `fsr-multi.sh`, `fsr412.sh`, `mfgunlocker.sh`, `opennr.sh`, `venom.sh`, `luma.sh`, `llayer-fg.sh` | Logic for the conf of the same name. |

## Files and logs

- Downloads: `~/.local/share/scopebuddy-dlls/<component>/` (`$SCB_DLLS`).
- Logs: `~/.config/scopebuddy/<conf>.log` (`cyboman`, `fsr-multi`, `opennr`, `venom`, `luma`).
- Per-game switches go in launch options before `scb`: `SCB_NO_RESET=1`, `SCB_NO_OPTIPATCHER=1`.
