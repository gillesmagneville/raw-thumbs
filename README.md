# raw-thumbnailer

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

## Compilation

Dépendances de build (Ubuntu 26.04) :

```
sudo apt install build-essential pkg-config libraw-dev cargo rustc
```

Puis :

```
cargo build --release
```

Le binaire final se trouve dans `target/release/raw-thumbnailer` (~750 Ko,
lié dynamiquement à `libraw_r`).

## Installation manuelle

Comme pour tout thumbnailer Nautilus, le binaire **doit** résider dans un
emplacement système — Nautilus exécute les thumbnailers dans un bac à
sable et refuse ceux situés dans `$HOME`.

```bash
sudo cp target/release/raw-thumbnailer /usr/local/bin/
sudo cp raw-thumbnailer.thumbnailer /usr/share/thumbnailers/
nautilus -q
rm -rf ~/.cache/thumbnails/*
```

Ouvrez ensuite un dossier contenant des fichiers RAW dans Nautilus pour
vérifier que les vignettes apparaissent.

## Empaquetage .deb

Le binaire et le fichier `.thumbnailer` s'intègrent directement dans le
même schéma que Planche-Contact (`build-deb.sh`, `postinst`) : il suffit
d'installer le binaire dans `/usr/bin` et le `.thumbnailer` dans
`/usr/share/thumbnailers/` via le paquet, sans venv Python à gérer cette
fois puisque tout est compilé statiquement à l'exception de la liaison
dynamique vers `libraw_r` (dépendance `libraw` à déclarer dans le
contrôle Debian).

## Format des types MIME couverts

Voir `raw-thumbnailer.thumbnailer` — la liste peut être étendue si un
format RAW spécifique n'est pas reconnu (vérifier le type MIME réel avec
`file --mime-type mon_fichier.xyz` ou `xdg-mime query filetype`).

## Tests

Validé sur un NEF Nikon réel (30 Mo) : extraction de vignette embarquée
~1 s (dominé par l'identification du fichier par libraw lui-même, pas par
le code Rust), décodage complet en repli ~6 s. Gestion propre des fichiers
invalides ou non-RAW (code de sortie non nul, aucun fichier de sortie
créé, pas de panique).
