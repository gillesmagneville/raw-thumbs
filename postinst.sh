#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
#
# Post-install script (fpm --after-install), run as root by dpkg.
# Deliberately informational only: a postinst script runs as root and $HOME
# is /root there, not the real user's home folder -- so ~/.cache/thumbnails
# is not touched automatically (fragile to do correctly for the user who
# invoked sudo/apt); the script just tells the user what to do.
#
# The message follows the system language: English, French, Spanish or
# German, falling back to English. The language is chosen by the rules of
# gettext: take the first non-empty variable among LANGUAGE, LC_ALL,
# LC_MESSAGES and LANG; it may hold several languages separated by ":", the
# first available language wins; "C" and "POSIX" stop the search (English).
# The pick_language block is deliberately identical to the one in
# nautilus-convert-images's postinst.
#
# The messages are in UTF-8 (accents, umlauts): a session whose language is
# French, Spanish or German is in UTF-8 on any current system.
set -e

pick_language() {
    _lang=en
    _list=
    for _var in "${LANGUAGE:-}" "${LC_ALL:-}" "${LC_MESSAGES:-}" "${LANG:-}"; do
        if [ -n "$_var" ]; then
            _list=$_var
            break
        fi
    done
    _old_ifs=$IFS
    IFS=:
    set -f
    for _entry in $_list; do
        case $_entry in
            C | C.* | POSIX | POSIX.*) break ;;
            fr | fr_* | fr.* | fr@*) _lang=fr; break ;;
            es | es_* | es.* | es@*) _lang=es; break ;;
            de | de_* | de.* | de@*) _lang=de; break ;;
        esac
    done
    set +f
    IFS=$_old_ifs
    echo "$_lang"
}

echo ""
case "$(pick_language)" in
    fr)
        echo "raw-thumbs est installé."
        echo "Si Nautilus était déjà ouvert, fermez-le complètement puis rouvrez-le"
        echo "pour que les nouvelles vignettes RAW prennent effet :"
        ;;
    es)
        echo "raw-thumbs está instalado."
        echo "Si Nautilus ya estaba abierto, ciérrelo por completo y vuelva a abrirlo"
        echo "para que las nuevas miniaturas RAW surtan efecto:"
        ;;
    de)
        echo "raw-thumbs wurde installiert."
        echo "Falls Nautilus bereits geöffnet war, beenden Sie es vollständig und"
        echo "starten Sie es neu, damit die neuen RAW-Vorschaubilder wirksam werden:"
        ;;
    *)
        echo "raw-thumbs installed."
        echo "If Nautilus was already open, close it completely and reopen it"
        echo "for the new RAW thumbnails to take effect:"
        ;;
esac
echo ""
echo "  killall nautilus"
echo "  rm -rf ~/.cache/thumbnails"
echo ""

exit 0
