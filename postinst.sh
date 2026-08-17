#!/bin/sh
# Script post-installation (fpm --after-install), execute en root par dpkg.
# Deliberement informatif seulement : un script postinst tourne en root et
# $HOME y vaut /root, pas le dossier personnel de l'utilisateur reel -- on
# ne touche donc pas a ~/.cache/thumbnails automatiquement (fragile a faire
# correctement pour l'utilisateur invoquant sudo/apt), on se contente de
# lui dire quoi faire.
set -e

echo ""
echo "raw-thumbs installe."
echo "Si Nautilus etait deja ouvert, fermez-le completement puis rouvrez-le"
echo "pour que les nouvelles vignettes RAW prennent effet :"
echo ""
echo "  killall nautilus"
echo "  rm -rf ~/.cache/thumbnails"
echo ""

exit 0
