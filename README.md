# raw-thumbs

Thumbnailer RAW pour Nautilus / GNOME Files, écrit en Rust, s'appuyant sur
**libraw** (bindings FFI via `libraw-sys`) pour couvrir la quasi-totalité
des formats RAW du marché (Canon CR2/CR3/CRW, Nikon NEF/NRW, Sony ARW/SR2,
Fuji RAF, Panasonic RW2, Olympus ORF, Pentax PEF, Adobe DNG, Sigma X3F,
Kodak DCR/KDC, Hasselblad 3FR, Phase One IIQ, etc.).

## Stratégie

1. **Vignette embarquée** (`libraw_unpack_thumb` + `libraw_dcraw_make_mem_thumb`) :
   chemin rapide, couvre la grande majorité des fichiers réels.
2. **Décodage complet** (`libraw_unpack` + `libraw_dcraw_process` +
   `libraw_dcraw_make_mem_image`) : repli automatique pour les RAW sans
   vignette embarquée exploitable.

Dans les deux cas, le décodage est fait par libraw (bibliothèque C liée
dynamiquement) — Rust n'orchestre que les appels, le redimensionnement
(crate `image`, filtre Lanczos3) et l'écriture PNG.

## Pourquoi pas le "raw-thumbnailer" existant ?

Il existe déjà un projet nommé `raw-thumbnailer` / `gnome-raw-thumbnailer`
(gitlab.gnome.org/World/gnome-raw-thumbnailer, maintenu par l'auteur de
libopenraw, packagé sur SUSE et l'AUR), ainsi qu'un remplaçant en Rust pur
nommé `miniaturo`. Les deux s'appuient sur **libopenraw**, dont la base de
formats caméra est historiquement plus restreinte que celle de **libraw**
— d'où le choix d'un moteur différent et d'un nom distinct pour ce projet.

## Compilation & empaquetage

Dépendances de build (Ubuntu 26.04) :

```bash
sudo apt install build-essential pkg-config libraw-dev cargo rustc
```

**Paquet `.deb`** (méthode recommandée) — `build-deb.sh` suit les mêmes
principes que celui de [linuxdoctor](https://github.com/gillesmagneville/linuxdoctor)
(et, plus loin, de Planche-Contact) : versionnage interactif ou par flag,
`VERSION`/`Cargo.toml` mis à jour uniquement après un build réussi,
staging dans un dossier temporaire avec permissions normalisées. Utilise
[fpm](https://fpm.readthedocs.io/) — installer avec
`gem install --user-install fpm` si absent.

```bash
./build-deb.sh --patch              # ou --minor / --major / --no-version-change
./build-deb.sh --patch --yes        # sans confirmation interactive
./build-deb.sh --clean              # supprime le dossier de build et les .deb générés
```

Avant la première utilisation, éditez `MAINTAINER` et `URL` en tête du
script — ce sont des valeurs à personnaliser. Le paquet généré installe
le binaire dans `/usr/bin/raw-thumbs`, le fichier `raw-thumbs.thumbnailer`
dans `/usr/share/thumbnailers/`, déclare une dépendance sur
`libraw23t64` (le paquet fournissant `libraw_r.so` sur Ubuntu 26.04 —
à vérifier si vous construisez sur une autre distribution), et affiche
après installation un rappel pour redémarrer Nautilus :

```bash
sudo apt install ./raw-thumbs_<version>_amd64.deb
```

**Compilation seule**, sans empaquetage :

```bash
cargo build --release
```

Le binaire final se trouve dans `target/release/raw-thumbs` (~750 Ko,
lié dynamiquement à `libraw_r`).

## Installation manuelle (développement uniquement)

Pour itérer rapidement sans repasser par `build-deb.sh` à chaque
changement :

Comme pour tout thumbnailer Nautilus, le binaire **doit** résider dans un
emplacement système. Attention : ça ne veut *pas* dire n'importe quel
emplacement système — Nautilus exécute les thumbnailers dans un bac à
sable bubblewrap qui ne monte que `/usr`, `/lib`, `/lib64`, `/proc`,
`/dev` et le fichier en cours de traitement. **`/usr/local` n'est jamais
monté** : un binaire installé là est invisible depuis l'intérieur du
sandbox et échoue silencieusement (`execve` → ENOENT), sans erreur
visible côté utilisateur — bug GNOME connu, documenté depuis 2018
(Debian #902288, gnome-desktop#71). Il faut donc installer dans
`/usr/bin`, pas `/usr/local/bin` :

```bash
sudo cp target/release/raw-thumbs /usr/bin/
sudo cp raw-thumbs.thumbnailer /usr/share/thumbnailers/
killall nautilus
rm -rf ~/.cache/thumbnails/*
```

Ouvrez ensuite un dossier contenant des fichiers RAW dans Nautilus pour
vérifier que les vignettes apparaissent.

> Installer manuellement dans `/usr/bin` sort du usage prévu par la
> norme FHS (réservé aux paquets gérés par le gestionnaire de paquets).
> La solution propre à terme est d'empaqueter en `.deb` (voir
> ci-dessus), qui installe légitimement dans `/usr/bin` via dpkg.

## Format des types MIME couverts

Voir `raw-thumbs.thumbnailer` — la liste peut être étendue si un
format RAW spécifique n'est pas reconnu (vérifier le type MIME réel avec
`file --mime-type mon_fichier.xyz` ou `xdg-mime query filetype`).

## Tests

Validé sur un NEF Nikon réel, un CR2 Canon et un ARW Sony : extraction de vignette embarquée
~1 s (dominé par l'identification du fichier par libraw lui-même, pas par
le code Rust), décodage complet en repli ~6 s. Gestion propre des fichiers
invalides ou non-RAW (code de sortie non nul, aucun fichier de sortie
créé, pas de panique).
