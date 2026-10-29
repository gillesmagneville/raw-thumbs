#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Teste postinst.sh : le message affiche a l'installation doit suivre la langue
# du systeme (anglais, francais, espagnol, allemand ; repli sur l'anglais).
# Depuis la racine du depot :
#
#   tests/test-postinst.sh
#
# Le script est execute sous plusieurs interpreteurs sh et avec de faux
# « killall » et « rm » qui prouvent qu'il ne fait qu'AFFICHER les commandes.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/postinst.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
fail() { echo "  [ECHEC] $*"; FAIL=$((FAIL + 1)); }
pass() { PASS=$((PASS + 1)); }

# Faux killall/rm : s'ils sont appeles, ils laissent une trace.
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

# Un fragment de la premiere phrase, propre a chaque langue.
marker() {
    case "$1" in
        en) echo "raw-thumbs installed." ;;
        fr) echo "raw-thumbs est installé." ;;
        es) echo "raw-thumbs está instalado." ;;
        de) echo "raw-thumbs wurde installiert." ;;
    esac
}

# detect_lang "<sortie>" : en/fr/es/de si exactement un message est reconnu.
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

# check <shell> <langue attendue> [VAR=valeur ...]
check() {
    local shell="$1" expected="$2"; shift 2
    local out err rc got desc="$*"
    err="$TMP/err"
    rm -f "$TMP/called"
    out="$(env -i PATH="$TMP/bin:$SYSBIN" HOME="$TMP/home" "$@" "$shell" "$SCRIPT" 2>"$err")"; rc=$?
    got="$(detect_lang "$out")"
    # bash se plaint lui-meme quand la locale demandee n'est pas installee sur
    # la machine : ce n'est pas le fait du script, on l'ignore.
    grep -v 'setlocale' "$err" > "$err.filtered" || true
    mv "$err.filtered" "$err"
    if [ "$rc" -ne 0 ]; then
        fail "[$shell] ${desc:-(aucune variable)} : code de sortie $rc"
    elif [ -s "$err" ]; then
        fail "[$shell] ${desc:-(aucune variable)} : message sur stderr : $(head -1 "$err")"
    elif [ "$got" != "$expected" ]; then
        fail "[$shell] ${desc:-(aucune variable)} : langue $got au lieu de $expected"
    elif ! grep -qxF "  killall nautilus" <<<"$out" || ! grep -qxF "  rm -rf ~/.cache/thumbnails" <<<"$out"; then
        fail "[$shell] ${desc:-(aucune variable)} : les deux commandes à recopier ne sont pas affichées"
    elif [ -e "$TMP/called" ]; then
        fail "[$shell] ${desc:-(aucune variable)} : le script a EXÉCUTÉ une commande : $(cat "$TMP/called")"
    else
        pass
    fi
}

SHELLS=(/bin/sh)
for s in dash bash; do
    p="$(command -v "$s" 2>/dev/null || true)"
    [ -n "$p" ] && SHELLS+=("$p")
done
# Sans doublon.
mapfile -t SHELLS < <(printf '%s\n' "${SHELLS[@]}" | awk '!seen[$0]++')

echo "Interpréteurs testés : ${SHELLS[*]}"

for sh in "${SHELLS[@]}"; do
    # Syntaxe.
    if ! "$sh" -n "$SCRIPT"; then fail "[$sh] erreur de syntaxe"; else pass; fi

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
    # Langues sans traduction : repli sur l'anglais.
    check "$sh" en LANG=it_IT.UTF-8
    check "$sh" en LANG=ja_JP.UTF-8
    check "$sh" en LANG=pt_BR.UTF-8
    check "$sh" en LANG=franglais
    # Priorite des variables, comme gettext.
    check "$sh" de LC_ALL=de_DE.UTF-8 LANG=fr_FR.UTF-8
    check "$sh" en LC_ALL=C LANG=fr_FR.UTF-8
    check "$sh" es LC_MESSAGES=es_ES.UTF-8 LANG=fr_FR.UTF-8
    check "$sh" fr LC_ALL= LC_MESSAGES= LANG=fr_FR.UTF-8
    check "$sh" de LANGUAGE=de LC_ALL=fr_FR.UTF-8
    check "$sh" es LANGUAGE= LANG=es_ES.UTF-8
    # LANGUAGE : liste, la premiere langue disponible gagne.
    check "$sh" de LANGUAGE=de:fr LANG=fr_FR.UTF-8
    check "$sh" de LANGUAGE=it:de LANG=fr_FR.UTF-8
    check "$sh" es LANGUAGE=it:ja:es_ES:fr LANG=en_US.UTF-8
    check "$sh" fr LANGUAGE=fr_FR:fr:en_US:en
    check "$sh" en LANGUAGE=en_US:en LANG=en_US.UTF-8
    check "$sh" en LANGUAGE=it LANG=fr_FR.UTF-8
    check "$sh" en LANGUAGE=C:fr LANG=fr_FR.UTF-8
    check "$sh" en LANGUAGE=it:C:de
    # Valeurs bizarres : jamais d'erreur.
    check "$sh" en 'LANGUAGE=*'
    check "$sh" fr 'LANGUAGE=*:fr'
    check "$sh" en LANGUAGE=::
done

echo
if [ "$FAIL" -eq 0 ]; then
    echo "RÉSULTAT : TOUT EST OK ($PASS vérifications réussies, 0 échec)"
else
    echo "RÉSULTAT : $FAIL ÉCHEC(S) ($PASS vérifications réussies)"
fi
[ "$FAIL" -eq 0 ]
