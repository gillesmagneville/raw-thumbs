#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Tests postinst.sh: the message shown at install time must follow the
# system language (English, French, Spanish, German; falling back to
# English). From the root of the repository:
#
#   tests/test-postinst.sh
#
# The script is run under several sh interpreters and with fake "killall"
# and "rm" commands that prove it only PRINTS the commands.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/postinst.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
fail() { echo "  [FAIL] $*"; FAIL=$((FAIL + 1)); }
pass() { PASS=$((PASS + 1)); }

# Fake killall/rm: if they are called, they leave a trace.
mkdir "$TMP/bin" "$TMP/home"
for tool in killall rm; do
    printf '#!/bin/sh\necho "%s $*" >> "%s/called"\n' "$tool" "$TMP" > "$TMP/bin/$tool"
    chmod +x "$TMP/bin/$tool"
done
SYSBIN="$TMP/sysbin"
mkdir "$SYSBIN"
for tool in sh dash bash echo cat env; do
    found="$(command -v "$tool" 2>/dev/null || true)"
    [ -n "$found" ] && ln -s "$found" "$SYSBIN/$tool"
done

# A fragment of the first sentence, specific to each language.
marker() {
    case "$1" in
        en) echo "raw-thumbs installed." ;;
        fr) echo "raw-thumbs est installé." ;;
        es) echo "raw-thumbs está instalado." ;;
        de) echo "raw-thumbs wurde installiert." ;;
    esac
}

# detect_lang "<output>": en/fr/es/de if exactly one message is recognized.
detect_lang() {
    local out="$1" found="" l
    for l in en fr es de; do
        if grep -qF -- "$(marker "$l")" <<<"$out"; then found="$found $l"; fi
    done
    found="${found# }"
    case "$found" in
        en | fr | es | de) echo "$found" ;;
        *) echo "?($found)" ;;
    esac
}

# check <shell> <expected language> [VAR=value ...]
check() {
    local shell="$1" expected="$2"; shift 2
    local out err rc got desc="$*"
    err="$TMP/err"
    rm -f "$TMP/called"
    out="$(env -i PATH="$TMP/bin:$SYSBIN" HOME="$TMP/home" "$@" "$shell" "$SCRIPT" 2>"$err")"; rc=$?
    got="$(detect_lang "$out")"
    # bash itself complains when the requested locale is not installed on
    # the machine: that is not the script's doing, so it is ignored.
    grep -v 'setlocale' "$err" > "$err.filtered" || true
    mv "$err.filtered" "$err"
    if [ "$rc" -ne 0 ]; then
        fail "[$shell] ${desc:-(no variable)}: exit code $rc"
    elif [ -s "$err" ]; then
        fail "[$shell] ${desc:-(no variable)}: message on stderr: $(head -1 "$err")"
    elif [ "$got" != "$expected" ]; then
        fail "[$shell] ${desc:-(no variable)}: language $got instead of $expected"
    elif ! grep -qxF "  killall nautilus" <<<"$out" || ! grep -qxF "  rm -rf ~/.cache/thumbnails" <<<"$out"; then
        fail "[$shell] ${desc:-(no variable)}: the two commands to copy are not displayed"
    elif [ -e "$TMP/called" ]; then
        fail "[$shell] ${desc:-(no variable)}: the script EXECUTED a command: $(cat "$TMP/called")"
    else
        pass
    fi
}

SHELLS=(/bin/sh)
for s in dash bash; do
    p="$(command -v "$s" 2>/dev/null || true)"
    [ -n "$p" ] && SHELLS+=("$p")
done
# No duplicates.
mapfile -t SHELLS < <(printf '%s\n' "${SHELLS[@]}" | awk '!seen[$0]++')

echo "Shells tested: ${SHELLS[*]}"

for sh in "${SHELLS[@]}"; do
    # Syntax.
    if ! "$sh" -n "$SCRIPT"; then fail "[$sh] syntax error"; else pass; fi

    check "$sh" en
    check "$sh" en LANG=en_US.UTF-8
    check "$sh" en LANG=C
    check "$sh" en LANG=C.UTF-8
    check "$sh" en LANG=POSIX
    check "$sh" fr LANG=fr_FR.UTF-8
    check "$sh" fr LANG=fr_CA.UTF-8
    check "$sh" fr LANG=fr
    check "$sh" fr LANG=fr_BE@euro
    check "$sh" es LANG=es_ES.UTF-8
    check "$sh" es LANG=es_MX.UTF-8
    check "$sh" es LANG=es
    check "$sh" de LANG=de_DE.UTF-8
    check "$sh" de LANG=de_AT.UTF-8
    check "$sh" de LANG=de_CH.ISO-8859-1
    check "$sh" de LANG=de_DE@euro
    # Languages without a translation: fall back to English.
    check "$sh" en LANG=it_IT.UTF-8
    check "$sh" en LANG=ja_JP.UTF-8
    check "$sh" en LANG=pt_BR.UTF-8
    check "$sh" en LANG=franglais
    # Variable priority, like gettext.
    check "$sh" de LC_ALL=de_DE.UTF-8 LANG=fr_FR.UTF-8
    check "$sh" en LC_ALL=C LANG=fr_FR.UTF-8
    check "$sh" es LC_MESSAGES=es_ES.UTF-8 LANG=fr_FR.UTF-8
    check "$sh" fr LC_ALL= LC_MESSAGES= LANG=fr_FR.UTF-8
    check "$sh" de LANGUAGE=de LC_ALL=fr_FR.UTF-8
    check "$sh" es LANGUAGE= LANG=es_ES.UTF-8
    # LANGUAGE: a list, the first available language wins.
    check "$sh" de LANGUAGE=de:fr LANG=fr_FR.UTF-8
    check "$sh" de LANGUAGE=it:de LANG=fr_FR.UTF-8
    check "$sh" es LANGUAGE=it:ja:es_ES:fr LANG=en_US.UTF-8
    check "$sh" fr LANGUAGE=fr_FR:fr:en_US:en
    check "$sh" en LANGUAGE=en_US:en LANG=en_US.UTF-8
    check "$sh" en LANGUAGE=it LANG=fr_FR.UTF-8
    check "$sh" en LANGUAGE=C:fr LANG=fr_FR.UTF-8
    check "$sh" en LANGUAGE=it:C:de
    # Odd values: never an error.
    check "$sh" en 'LANGUAGE=*'
    check "$sh" fr 'LANGUAGE=*:fr'
    check "$sh" en LANGUAGE=::
done

echo
if [ "$FAIL" -eq 0 ]; then
    echo "RESULT: ALL OK ($PASS checks passed, 0 failures)"
else
    echo "RESULT: $FAIL FAILURE(S) ($PASS checks passed)"
fi
[ "$FAIL" -eq 0 ]
