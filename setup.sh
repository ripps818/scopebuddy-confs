#!/usr/bin/env bash
# Copies the confs and lib/ into ~/.config/scopebuddy and checks the DLLs that are not auto-downloaded.
set -u
here=$(cd "$(dirname "$0")" && pwd)
cfg="${SCB_CONFIGDIR:-$HOME/.config/scopebuddy}"
data="${XDG_DATA_HOME:-$HOME/.local/share}"
dlls="${SCB_DLLS:-$data/scopebuddy-dlls}"

mkdir -p "$cfg/AppID"
for f in "$here"/*.conf; do
    dst="$cfg/$(basename "$f")"
    [ -e "$dst" ] && ! cmp -s "$f" "$dst" && cp -f "$dst" "$dst.bak"
    cp -f "$f" "$dst"
done
# move the old per-tool folders into $dlls (old=new)
mkdir -p "$dlls"
for m in mfg-unlocker=mfg-unlocker optipatcher=optipatcher fsr-multi=fsr-multi helixsr-scb=helixsr opennr-scb=opennr \
         fsr4-dll=cyboman fsr4-shader-performance-overrides=cyboman-repo fsr4-dump=cyboman-dump \
         fsr4-4.1.2=fsrsdk fsr4-driver-4.1.2=fsr4-driver-4.1.2 low-latency-layer-fg=low-latency-layer-fg; do
    [ -d "$data/${m%%=*}" ] && [ ! -e "$dlls/${m#*=}" ] && mv "$data/${m%%=*}" "$dlls/${m#*=}" && echo "moved ${m%%=*} -> $dlls/${m#*=}"
done

mkdir -p "$cfg/lib"
cp -f "$here"/lib/*.sh "$cfg/lib/"
for f in helixsr optiscaler-reset hdr dualsense dualsense-ge gamemode afmf nvapi reflex optiscaler-log optipatcher; do
    [ -e "$cfg/$f.conf" ] && echo "NOTE: $cfg/$f.conf is obsolete; remove it once no game sources it"
done
echo "confs installed to $cfg (changed files backed up as .bak), scripts in $cfg/lib"

# Auto-downloaded on first launch: cyboman, fsr-multi (cyboman/hlx), fsrsdk, opennr, venom, mfgunlocker, optipatcher.
# Not handled here: opennr's neural backend files, the HelixSR DLSS network build, and the driver files (fsr4-driver-4.1.2).
