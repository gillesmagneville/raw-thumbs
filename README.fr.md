# raw-thumbs

🇬🇧 [English version](README.md)

**Ubuntu n'a plus de thumbnailer RAW dans ses dépôts depuis la 20.04 LTS**
(le dernier, `gnome-raw-thumbnailer`, date de la 18.04). raw-thumbs rétablit
les vignettes RAW dans Nautilus, y compris pour les fichiers sans aperçu
intégré.

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

`gnome-raw-thumbnailer` n'est d'ailleurs plus dans les dépôts Ubuntu depuis
la 20.04 LTS (dernière version : 18.04, vérifié avec
`rmadison -u ubuntu gnome-raw-thumbnailer`).

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
après installation un rappel pour redémarrer Nautilus (dans la langue du système) :

```bash
sudo apt install ./raw-thumbs_<version>_amd64.deb
```

**Compilation seule**, sans empaquetage :

```bash
cargo build --release
```

Le binaire final se trouve dans `target/release/raw-thumbs` (~750 Ko,
lié dynamiquement à `libraw_r`).

### Publier une release

`release.sh` publie la release GitHub correspondant à `VERSION`, comme dans
nautilus-convert-images. `VERSION` n'avance que par `build-deb.sh` ; l'ordre
habituel est donc :

```bash
./build-deb.sh --patch --yes     # fait avancer VERSION (ou --minor / --major)
./release.sh --dry-run           # affiche tout, ne modifie rien
./release.sh                     # publie, après confirmation
```

Il vérifie la branche, le dépôt distant, que le tag est libre et que le
fichier `.thumbnailer` pointe vers `/usr/bin` ; lance
`tests/test-postinst.sh` ; transforme `## [Unreleased]` de `CHANGELOG.md` en
`## [X.Y.Z] - date` et en tire les notes de la release (une sous-section
facultative `### English summary` devient la partie « English summary ») ;
reconstruit le `.deb` si quelque chose qu'il contient a changé et l'inspecte
(version, dépendance, fichiers identiques à ceux du dépôt, script
d'installation) ; puis valide, pousse et crée la release avec le `.deb` et son
`.sha256`. Il faut `git`, `gh` (connecté avec `gh auth login`), `dpkg-deb` et
`python3`, plus `cargo` et `fpm` pour la reconstruction.

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

> Installer manuellement dans `/usr/bin` sort de l'usage prévu par la
> norme FHS (réservé aux paquets gérés par le gestionnaire de paquets).
> La solution propre à terme est d'empaqueter en `.deb` (voir
> ci-dessus), qui installe légitimement dans `/usr/bin` via dpkg.

## Format des types MIME couverts

Voir `raw-thumbs.thumbnailer` — la liste peut être étendue si un
format RAW spécifique n'est pas reconnu (vérifier le type MIME réel avec
`file --mime-type mon_fichier.xyz` ou `xdg-mime query filetype`).

## Langues

raw-thumbs n'a ni fenêtre ni menu : Nautilus affiche simplement les
vignettes. Le seul texte destiné à une personne est le rappel affiché à
l'installation du `.deb`. Il suit la langue de votre système — **anglais,
français, espagnol ou allemand**, et anglais pour toute autre langue (mêmes
règles que `gettext` : variables `LANGUAGE`, `LC_ALL`, `LC_MESSAGES` ou
`LANG`).

* Les textes espagnol et allemand n'ont pas encore été relus par des
  locuteurs natifs : les corrections sont les bienvenues.
* Les messages de diagnostic que le programme écrit sur sa sortie d'erreur
  (visibles seulement si vous le lancez à la main dans un terminal) sont en
  anglais.
* L'entrée de menu contextuel « Convertir les images… » ne fait pas partie de
  raw-thumbs : elle appartient au projet distinct nautilus-convert-images,
  disponible dans les mêmes quatre langues.

## Tests

`tests/test-postinst.sh` exécute le script d'installation sous plusieurs
interpréteurs et réglages de langue (anglais, français, espagnol, allemand,
langues non gérées, priorité des variables, listes `LANGUAGE`) et vérifie
qu'il se contente d'*afficher* les deux commandes à lancer, sans jamais les
exécuter.

Validé sur un NEF Nikon réel, un CR2 Canon et un ARW Sony : extraction de vignette embarquée
~1 s (dominé par l'identification du fichier par libraw lui-même, pas par
le code Rust), décodage complet en repli ~6 s. Gestion propre des fichiers
invalides ou non-RAW (code de sortie non nul, aucun fichier de sortie
créé, pas de panique).

## Licence

GPL-3.0-only. Voir [LICENSE](LICENSE).

raw-thumbs est développé par Gilles MAGNEVILLE. Gilles n'est pas développeur
professionnel — ce projet a été construit avec l'aide de Claude.ai.
