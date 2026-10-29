#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
#
# Script post-installation (fpm --after-install), execute en root par dpkg.
# Deliberement informatif seulement : un script postinst tourne en root et
# $HOME y vaut /root, pas le dossier personnel de l'utilisateur reel -- on
# ne touche donc pas a ~/.cache/thumbnails automatiquement (fragile a faire
# correctement pour l'utilisateur invoquant sudo/apt), on se contente de
# lui dire quoi faire.
#
# Le message suit la langue du systeme : anglais, francais, espagnol ou
# allemand, avec repli sur l'anglais. La langue est choisie selon les regles
# de gettext : on prend la premiere variable non vide parmi LANGUAGE, LC_ALL,
# LC_MESSAGES et LANG ; elle peut contenir plusieurs langues separees par
# ":", la premiere langue disponible gagne ; "C" et "POSIX" arretent la
# recherche (anglais). Le bloc pick_language est volontairement identique a
# celui du postinst de nautilus-convert-images.
#
# Les messages sont en UTF-8 (accents, trema) : une session dont la langue est
# le francais, l'espagnol ou l'allemand est en UTF-8 sur tout systeme actuel.
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
