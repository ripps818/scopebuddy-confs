# lib/cyboman-release.sh: zgauthier2000/fsr4-shader-performance-overrides release lookups,
# shared by cyboman.sh and fsr-multi.sh. Needs common.sh.
_CYBOMAN_GH="https://github.com/zgauthier2000/fsr4-shader-performance-overrides"

scb_cyboman_tag() {   # newest dll-* release tag (needs git)
    scb_host timeout 20 git ls-remote --tags --refs "$_CYBOMAN_GH.git" 'dll-*' 2>/dev/null \
        | sed 's|.*refs/tags/||' | sort -V | tail -n1
}

scb_cyboman_prefix() {   # target -> regex for that GPU target's zip name
    case "$1" in
        rx7000|rx6000) printf 'fsr4[.]1[.][0-9]-cyboman-%s' "$1" ;;
        igpu-rdna3|igpu-rdna2) printf 'fsr4[.]1[.][0-9]-igpu-cyboman-%s' "${1#igpu-}" ;;
        *) return 1 ;;
    esac
}

scb_cyboman_asset() {   # sums-file prefix -> zip name (it carries the release date)
    awk -v p="$2" '$2 ~ "^" p "(-[0-9][0-9.-]*)?\\.zip$" {print $2; exit}' "$1"
}
