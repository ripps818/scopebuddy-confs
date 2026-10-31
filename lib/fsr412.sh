# lib/fsr412.sh: logic for fsr412.conf (see that file for usage and FSR412_CLEANUP).
_scb_lib="${BASH_SOURCE[0]%/*}"
source "$_scb_lib/common.sh"
unset _scb_lib

export LOW_LATENCY_LAYER=1

FSR412_SRC="$SCB_DLLS/fsr4-4.1.2"
FSR412_DST="$STEAM_COMPAT_DATA_PATH/pfx/drive_c/windows/system32/umu/OptiScaler"
FSR412_FILES="amd_fidelityfx_upscaler_dx12.dll amd_fidelityfx_upscaler_vk.dll"
# Cleanup: set FSR412_CLEANUP=1 above the source line for one launch to remove the files
# this script copied (only byte-identical ones), then drop the flag. Nothing is copied or
# exported on a cleanup launch.
if [ "${FSR412_CLEANUP:-0}" = 1 ]; then
    if [ -n "$STEAM_COMPAT_DATA_PATH" ]; then
        for f in $FSR412_FILES; do
            if [ -f "$FSR412_DST/$f" ] && cmp -s "$FSR412_SRC/$f" "$FSR412_DST/$f"; then
                rm -f "$FSR412_DST/$f"
            fi
        done
    fi
    return 0 2>/dev/null || true
fi

if [ -n "$STEAM_COMPAT_DATA_PATH" ] && [ -n "${PROTON_USE_OPTISCALER:-}" ] && [ "$PROTON_USE_OPTISCALER" != 0 ]; then
    mkdir -p "$FSR412_DST"
    for f in $FSR412_FILES; do
        cmp -s "$FSR412_SRC/$f" "$FSR412_DST/$f" 2>/dev/null || cp -f --reflink=auto "$FSR412_SRC/$f" "$FSR412_DST/$f"
    done
fi

# Force OptiScaler onto the INT8 model (RDNA3).
case "${PROTON_OPTISCALER_CONFIG:-}" in
    *FSR.Fsr4GpuSupport=*) ;;
    *)
        PROTON_OPTISCALER_CONFIG="${PROTON_OPTISCALER_CONFIG:+$PROTON_OPTISCALER_CONFIG;}FSR.UpscalerIndex=0;FSR.Fsr4GpuSupport=2"
        export PROTON_OPTISCALER_CONFIG
        ;;
esac
