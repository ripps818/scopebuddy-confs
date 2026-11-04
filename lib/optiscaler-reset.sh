# Reset the OptiScaler plugins our confs install, at the start of every launch.
# Source it at the top of scb.conf, before anything that installs plugins:
#   source "$SCB_CONFIGDIR/lib/optiscaler-reset.sh"
# ScopeBuddy sources scb.conf before the game's AppID conf, so this can't know which confs the
# game will use: it clears them all, and the confs the game sources (lib/optipatcher.sh,
# mfgunlocker.conf, ...) put back what it uses. A plugin is only present on a launch that asked
# for it, so commenting a conf out is enough to remove it.
#
# Only our own files are touched: Proton's OptiScaler install, OptiScaler.ini and anything else in
# the folders are left alone. Settings a conf added to OptiScaler.ini (e.g. FGOutput=XeFG) stay
# until Proton writes a fresh ini; put the settings you want in PROTON_OPTISCALER_CONFIG.
# fsrsdk.conf's DLLs are cleared too, but only copies byte-identical to the ones in
# ~/.local/share/scopebuddy-dlls/fsrsdk (Proton's own files are kept); fsrsdk.conf copies them back.
# Turn the reset off for a game with SCB_NO_RESET=1 in its launch options.
_scb_lib="${BASH_SOURCE[0]%/*}"
source "$_scb_lib/common.sh"
unset _scb_lib

if [ "${SCB_NO_RESET:-0}" != 1 ] && [ -n "${STEAM_COMPAT_DATA_PATH:-}" ]; then
    _reset_umu="$STEAM_COMPAT_DATA_PATH/pfx/drive_c/windows/system32/umu"
    # every name and place our confs have used
    for _reset_f in plugins/OptiPatcher-rolling.asi plugins/MFGUnlocker.asi \
                    OptiScaler/plugins/MFGUnlocker.asi; do
        rm -f "$_reset_umu/$_reset_f" 2>/dev/null || true
    done
    # fsr-multi.conf test copies
    rm -f "$_reset_umu"/OptiScaler/fsr-*.dll 2>/dev/null || true
    for _reset_f in "$SCB_DLLS"/fsr-multi/fsr-*.dll "$SCB_DLLS"/fsr-multi/dlss-*.dll; do
        _reset_f=${_reset_f##*/}; _reset_f=${_reset_f#fsr-}; _reset_f=${_reset_f#dlss-}
        rm -rf "$_reset_umu/OptiScaler/custom/${_reset_f%.dll}" 2>/dev/null || true
    done
    rmdir "$_reset_umu/OptiScaler/custom" 2>/dev/null || true
    _reset_d="$_reset_umu/OptiScaler"
    for _reset_src in "$SCB_DLLS/fsrsdk" "$SCB_DLLS/fsr4-4.1.2"; do   # fsr4-4.1.2: the old folder name
        for _reset_f in amd_fidelityfx_upscaler_dx12.dll amd_fidelityfx_upscaler_vk.dll; do
            if [ -f "$_reset_d/$_reset_f" ] && cmp -s "$_reset_src/$_reset_f" "$_reset_d/$_reset_f"; then
                rm -f "$_reset_d/$_reset_f" 2>/dev/null || true
            fi
        done
    done
    # legacy driver-DLL install (fsr4-driver-4.1.2); works while that directory still exists
    _reset_src="$SCB_DLLS/fsr4-driver-4.1.2"
    for _reset_d in "$_reset_umu/OptiScaler" "$STEAM_COMPAT_DATA_PATH/pfx/drive_c/windows/system32"; do
        for _reset_f in amdxcffx64.dll amdvkffx64.dll amd_fidelityfx_upscaler_dx12.dll; do
            if [ -f "$_reset_d/$_reset_f" ] && cmp -s "$_reset_src/$_reset_f" "$_reset_d/$_reset_f"; then
                rm -f "$_reset_d/$_reset_f" 2>/dev/null || true
            fi
        done
        if [ -f "$_reset_d/fsr-original.dll" ] && cmp -s "$_reset_src/amdxcffx64.dll" "$_reset_d/fsr-original.dll"; then
            rm -f "$_reset_d/fsr-original.dll" 2>/dev/null || true
        fi
    done
    unset _reset_umu _reset_f _reset_d _reset_src
fi
