# Changelog

Toutes les modifications notables de ce projet sont documentées dans ce
fichier.

Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.0.0/),
et ce projet suit le [versionnage sémantique](https://semver.org/lang/fr/).

## [0.1.0] - 2026-08-18

### Ajouté

- Thumbnailer RAW pour Nautilus / GNOME Files écrit en Rust, appuyé sur
  **libraw** via des bindings FFI (`libraw-sys`).
- Extraction de vignette embarquée (`libraw_unpack_thumb` +
  `libraw_dcraw_make_mem_thumb`) : chemin rapide couvrant la grande
  majorité des fichiers RAW réels.
- Décodage RAW complet en repli (`libraw_unpack` + `libraw_dcraw_process`
  + `libraw_dcraw_make_mem_image`) pour les fichiers sans vignette
  embarquée exploitable.
- Couverture de la quasi-totalité des formats RAW du marché via libraw :
  Canon CR2/CR3/CRW, Nikon NEF/NRW, Sony ARW/SR2/SRF, Fuji RAF,
  Panasonic RAW/RW2, Olympus ORF, Pentax PEF/RAW, Adobe DNG, Sigma X3F,
  Kodak DCR/K25/KDC, Minolta MRW, Hasselblad 3FR, Phase One IIQ, Epson
  ERF, Mamiya MEF, Leaf MOS.
- Fichier d'enregistrement `raw-thumbs.thumbnailer` conforme à la
  spécification freedesktop.org thumbnailer, compatible avec le bac à
  sable bubblewrap de Nautilus/GNOME Files (installation en `/usr/bin`,
  seul emplacement monté dans le sandbox — `/usr/local` ne l'est pas).
- Empaquetage `.deb` via `build-deb.sh` (fpm).

### Corrigé

- Validé sur fichiers RAW réels (Sony ARW, Canon CR2) : aucune vignette
  concurrente enregistrée dans `~/.local/share/thumbnailers/` ou
  `/usr/local/share/thumbnailers/` ne doit rester active pour le même
  type MIME, sous peine d'échec silencieux masquant `raw-thumbs`.
