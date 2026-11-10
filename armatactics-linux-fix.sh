#!/usr/bin/env bash
# Arma Tactics (Linux, Steam) — launch fixes
#
#  1) ArmaTactics.x86: game quits at once with "Player is already running".
#     Unity 5.3's single-instance check scans /proc/*/cmdline and realpath()s
#     argv[0]. Some steamwebhelper processes have argv[0] "/proc/self/exe",
#     which resolves to the game itself, so the game thinks it is already
#     running whenever Steam is open. Fix: the check function (file offset
#     0xa8c6c0) returns 0.
#
#  2) Assembly-CSharp.dll: red "ERROR" and abort right after start
#     (ERR_REGISTRY_EMPTY). Steam Cloud may report a 0-byte 'registry' file;
#     the game treats that as fatal instead of "no save yet". Fix: in
#     CGameServicesSteam.StartDownload a 0-byte cloud file is treated as
#     NOT_FOUND, so the game creates default settings (in-place IL patch,
#     49 bytes at file offset 0x8aff6, method size unchanged).
#
# Only files with the exact expected SHA-256 are touched.
# To undo, reinstall the game or use Steam's "Verify integrity of game files".
#
# Usage: armatactics-linux-fix.sh [GAME_DIR]

set -euo pipefail

APPID=224860

EXE=ArmaTactics.x86
EXE_ORIG_SHA=b363ae47469fbb359de4da43f8cb45a4e58e46935ba25070b66a63d6ac125a81
EXE_PATCHED_SHA=a2fc24be19e1365671129cc670f6756ae411fe927d640d7bed4afa994149e34c
EXE_OFFSET=$((0xa8c6c0))
EXE_BYTES=31c0c3                    # xor eax,eax ; ret

DLL=ArmaTactics_Data/Managed/Assembly-CSharp.dll
DLL_ORIG_SHA=f8c468ce71b76df84f70354d08a59b4019c617226395fad3e36a655eea857dd8
DLL_PATCHED_SHA=56ae673b314ba942ca8bec054641cd7467a132742670fc1dfe01b3e6b5d7b10c
DLL_OFFSET=$((0x8aff6))
DLL_BYTES=2d2272e9e40170067205e50170282e00000a287f00000a0203061a142818160006262b5d0628ea07000a0b072cd4000000

die()  { echo "error: $*" >&2; exit 1; }
info() { echo ":: $*"; }

for t in sha256sum dd cp mv mktemp; do command -v "$t" >/dev/null || die "missing tool: $t"; done

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0; fi

find_game_dir() {
    local roots=("$HOME/.local/share/Steam" "$HOME/.steam/steam" "$HOME/.steam/root"
                 "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam")
    local r lib
    for r in "${roots[@]}"; do
        [[ -f "$r/steamapps/libraryfolders.vdf" ]] || continue
        while IFS= read -r lib; do
            if [[ -f "$lib/steamapps/appmanifest_$APPID.acf" && -f "$lib/steamapps/common/ArmaTactics/$EXE" ]]; then
                echo "$lib/steamapps/common/ArmaTactics"; return 0
            fi
        done < <(sed -n 's/^[[:space:]]*"path"[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$r/steamapps/libraryfolders.vdf")
    done
    return 1
}

sha() { sha256sum "$1" | cut -d' ' -f1; }

write_hex() {   # file offset hexstring
    local hex=$3 esc="" i
    for ((i = 0; i < ${#hex}; i += 2)); do esc+="\\x${hex:i:2}"; done
    printf '%b' "$esc" | dd of="$1" bs=1 seek="$2" conv=notrunc status=none
}

TMP=""
trap '[[ -n "$TMP" ]] && rm -f "$TMP"' EXIT

patch_file() {  # rel orig_sha patched_sha offset hex label
    local f="$GAME_DIR/$1" cur
    [[ -f "$f" ]] || die "$6: not found: $f"
    cur=$(sha "$f")
    if [[ "$cur" == "$3" ]]; then info "$6: already patched"; return; fi
    [[ "$cur" == "$2" ]] || die "$6: unknown version of $1 (sha256 $cur); nothing changed"
    # Patch a temporary copy, verify it, then replace the original in one step.
    TMP=$(mktemp "$f.XXXXXX")
    cp -p "$f" "$TMP"
    write_hex "$TMP" "$4" "$5"
    [[ "$(sha "$TMP")" == "$3" ]] || die "$6: verification failed; nothing changed"
    mv -f "$TMP" "$f"
    TMP=""
    info "$6: patched"
}

GAME_DIR=${1:-}
if [[ -z "$GAME_DIR" ]]; then
    GAME_DIR=$(find_game_dir) || die "Arma Tactics install not found; pass the game folder as an argument"
fi
[[ -f "$GAME_DIR/$EXE" ]] || die "$GAME_DIR does not look like the Arma Tactics folder"
info "game folder: $GAME_DIR"

if pgrep -x "$EXE" >/dev/null 2>&1; then die "the game is running; close it first"; fi

patch_file "$EXE" "$EXE_ORIG_SHA" "$EXE_PATCHED_SHA" "$EXE_OFFSET" "$EXE_BYTES" "single-instance fix"
patch_file "$DLL" "$DLL_ORIG_SHA" "$DLL_PATCHED_SHA" "$DLL_OFFSET" "$DLL_BYTES" "empty-registry fix"
info "done, start the game from Steam"
