# Changelog

🇬🇧 [English version](CHANGELOG.md)

Toutes les modifications notables de ce projet sont documentées dans ce
fichier.

Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.0.0/),
et ce projet suit le [versionnage sémantique](https://semver.org/lang/fr/).

## [Unreleased]

## [1.0.3] - 2026-10-29

### Ajouté

- **`release.sh`** : publie une release GitHub en une commande, sur le modèle
  de nautilus-convert-images (`--dry-run` pour tout voir sans rien modifier).
  Il vérifie le dépôt et les sources, lance `tests/test-postinst.sh`, tire les
  notes du CHANGELOG (« [Unreleased] » devient « [X.Y.Z] - date »), reconstruit
  et inspecte le `.deb`, puis valide, pousse et crée la release avec le `.deb`
  et son `.sha256`. Voir le README.
- Notes de release **en anglais d'abord, puis en français** (comme le README,
  anglais par défaut). Elles viennent de l'entrée de la version dans
  `CHANGELOG.md` (anglais) et dans `CHANGELOG.fr.md` (français) : `release.sh`
  s'arrête avant toute modification si l'une des deux manque ou est vide.
- **CHANGELOG bilingue** : `CHANGELOG.md` (anglais, affiché par défaut sur
  GitHub) et `CHANGELOG.fr.md` (français), avec un lien pour changer de langue
  en haut de chaque fichier. Les deux sont embarqués dans le paquet `.deb`.

## [1.0.2] - 2026-10-29

Aucun changement dans la génération des vignettes : cette version concerne les
messages affichés et la documentation.

### Modifié

- **Message d'installation dans la langue du système.** Le rappel affiché à
  l'installation du `.deb` (redémarrer Nautilus, vider le cache des vignettes)
  s'affiche en anglais, français, espagnol ou allemand selon la langue de la
  session (règles de gettext : `LANGUAGE`, `LC_ALL`, `LC_MESSAGES`, `LANG`),
  avec repli sur l'anglais pour toute autre langue. Il était auparavant
  uniquement en français (sans accents). Les textes espagnol et allemand n'ont
  pas été relus par des locuteurs natifs.
- **Messages de diagnostic en anglais.** Les messages écrits sur la sortie
  d'erreur (utilisation, taille invalide, échecs de libraw, de décodage ou
  d'écriture du PNG) étaient en français ; ils sont maintenant en anglais,
  langue des journaux. Ils ne sont visibles que si on lance `raw-thumbs` à la
  main : Nautilus les ignore.
- **Le README affiché par défaut sur GitHub est maintenant en anglais** :
  `README.md` est la version anglaise et la version française devient
  `README.fr.md` (`README.en.md` disparaît). Les deux sont embarqués dans le
  paquet `.deb`.
- **README : section Licence et mention de l'aide de Claude.** Les deux README
  indiquent la licence (GPL-3.0-only) et précisent que le projet a été construit
  avec l'aide de Claude.ai par un développeur non professionnel, comme dans
  nautilus-convert-images.

### Ajouté

- `tests/test-postinst.sh` : vérifie le message d'installation sous plusieurs
  interpréteurs sh et réglages de langue.

## [1.0.1] - 2026-10-28

### Corrigé

- Orientation EXIF/MakerNote non appliquée sur le chemin vignette
  embarquée (`libraw_unpack_thumb`/`libraw_dcraw_make_mem_thumb`) : les
  photos prises en portrait ou avec l'appareil tourné apparaissaient
  pivotées à 90°/180°. Le chemin décodage complet (`dcraw_make_mem_image`)
  n'était pas affecté — libraw y applique déjà la rotation en interne.
  Corrigé en lisant `libraw_image_sizes_t.flip` et en appliquant la
  rotation correspondante nous-mêmes uniquement sur la vignette
  embarquée. Validé sur un DNG iPhone (flip=6, mire ColorChecker) :
  logo et texte à l'endroit après correction, à l'envers avant.
- `Cargo.lock` : trois sommes de contrôle (`crc32fast`, `miniz_oxide`,
  `pkg-config`) étaient altérées depuis la v1.0.0, si bien que `cargo build`
  refusait de compiler depuis les sources (« checksum … changed between lock
  files »). Elles sont rétablies à leurs valeurs officielles, vérifiées
  contre crates.io. Pour compiler depuis les sources, utiliser la 1.0.1 ;
  le tag v1.0.0 reste tel quel.

### Ajouté

- README en anglais (`README.en.md`) et accroche : Ubuntu n'a plus de
  thumbnailer RAW dans ses dépôts depuis la 20.04 LTS.
- Fichier `LICENSE` (GPL-3.0-only, déjà déclarée dans les métadonnées du
  paquet), installé aussi dans `/usr/share/doc/raw-thumbs/`.

## [1.0.0] - 2026-08-18

### Modifié

- Première version stable : renumérotation de la 0.1.0, dont le code est
  inchangé ; `MAINTAINER` renseigné dans `build-deb.sh` et
  `.gitattributes` ajouté.

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
