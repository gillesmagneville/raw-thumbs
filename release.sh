#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

# ============================================================
# raw-thumbs - release.sh
#
# Publie la release stable GitHub correspondant au contenu de VERSION :
#   1. controles prealables (branche, remote, tag libre, sources, tests)
#   2. mise en coherence (Cargo.toml, CHANGELOG) puis reconstruction du
#      paquet si necessaire
#   3. verification du contenu du .deb
#   4. commit + push sur main
#   5. creation de la release (tag, notes, .deb, .sha256)
#
# Ordre habituel (VERSION n'avance que par build-deb.sh) :
#   ./build-deb.sh --patch --yes     # ou --minor / --major
#   ./release.sh --dry-run           # tout voir, rien modifier
#   ./release.sh
#
# Les notes de la release viennent du CHANGELOG : si la section de la
# version n'existe pas encore, le contenu de « ## [Unreleased] » devient
# « ## [X.Y.Z] - date ». Une sous-section « ### English summary » (facultative)
# est reprise dans la partie « English summary » des notes.
# ============================================================

REPO_SLUG="gillesmagneville/raw-thumbs"
PKG="raw-thumbs"
DRY_RUN=false
ASSUME_YES=false

show_help() {
  cat <<EOF
Usage: ./release.sh [options]

Publie la release stable GitHub de raw-thumbs (tag v\$(cat VERSION)).
A lancer depuis la racine du depot, apres ./build-deb.sh --patch --yes
(ou --minor / --major), qui fait avancer VERSION.

  --dry-run    Affiche ce qui serait fait (et les notes de release) sans rien
               modifier, committer, pousser ni publier
  --yes, -y    Ne pas demander de confirmation
  --help, -h   Affiche cette aide
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --yes|-y) ASSUME_YES=true; shift ;;
    --help|-h) show_help; exit 0 ;;
    *) echo "Option inconnue : $1" >&2; show_help >&2; exit 1 ;;
  esac
done

step() { printf '\n>>> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }
die()  { printf '\nErreur : %s\n' "$*" >&2; exit 1; }

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ------------------------------------------------------------
# 1. Controles prealables
# ------------------------------------------------------------
step "Controles prealables"

for t in git gh python3 sha256sum dpkg-deb cmp; do
  command -v "$t" >/dev/null 2>&1 || die "outil manquant : $t"
done

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "ce dossier n'est pas un depot git."
[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || die "la branche courante n'est pas 'main'."

ORIGIN_URL="$(git remote get-url origin 2>/dev/null)" || die "pas de remote 'origin'."
case "$ORIGIN_URL" in
  *"$REPO_SLUG"*) ;;
  *) die "origin ne pointe pas vers $REPO_SLUG ($ORIGIN_URL)." ;;
esac

if ! gh auth status >/dev/null 2>&1; then
  if $DRY_RUN; then
    warn "gh n'est pas authentifie (lancez 'gh auth login' avant la vraie publication)."
  else
    die "gh n'est pas authentifie : lancez 'gh auth login'."
  fi
fi

git fetch --quiet --tags origin || die "git fetch origin a echoue."
if git rev-parse -q --verify origin/main >/dev/null; then
  BEHIND="$(git rev-list --count HEAD..origin/main)"
  [ "$BEHIND" = "0" ] || die "origin/main contient $BEHIND commit(s) absent(s) en local : faites d'abord 'git pull --rebase'."
fi

[ -f VERSION ] || die "fichier VERSION introuvable."
VERSION="$(tr -d '[:space:]' < VERSION)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "VERSION invalide : '$VERSION' (attendu X.Y.Z)."
TAG="v$VERSION"

NEXT_HINT="Lancez d'abord ./build-deb.sh --patch --yes (ou --minor / --major) pour passer a la version suivante."
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  die "le tag $TAG existe deja en local : VERSION ($VERSION) est deja publiee. $NEXT_HINT"
fi
if git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
  die "le tag $TAG existe deja sur GitHub : VERSION ($VERSION) est deja publiee. $NEXT_HINT"
fi
if gh release view "$TAG" --repo "$REPO_SLUG" >/dev/null 2>&1; then
  die "une release $TAG existe deja sur GitHub. $NEXT_HINT"
fi

PREV_TAG="$(git tag -l 'v[0-9]*' --sort=-v:refname | grep -vxF "$TAG" | head -1 || true)"
if [ -n "$PREV_TAG" ]; then
  [ "$(printf '%s\n%s\n' "${PREV_TAG#v}" "$VERSION" | sort -V | tail -1)" = "$VERSION" ] \
    || die "VERSION ($VERSION) n'est pas superieure a la derniere release ($PREV_TAG)."
  info "Version : $VERSION  ->  tag $TAG  (derniere release : $PREV_TAG)"
else
  info "Version : $VERSION  ->  tag $TAG  (premiere release)"
fi

for f in src/main.rs raw-thumbs.thumbnailer postinst.sh build-deb.sh Cargo.toml Cargo.lock \
         CHANGELOG.md README.md README.fr.md LICENSE; do
  [ -f "$f" ] || die "fichier du projet introuvable : $f"
done

# Le fichier .thumbnailer doit pointer vers /usr/bin : le bac a sable
# bubblewrap de Nautilus ne monte jamais /usr/local (voir README).
grep -qx 'Exec=/usr/bin/raw-thumbs %i %o %s' raw-thumbs.thumbnailer \
  || die "raw-thumbs.thumbnailer : la ligne Exec doit etre exactement 'Exec=/usr/bin/raw-thumbs %i %o %s'."
grep -qx 'TryExec=/usr/bin/raw-thumbs' raw-thumbs.thumbnailer \
  || die "raw-thumbs.thumbnailer : la ligne TryExec doit etre exactement 'TryExec=/usr/bin/raw-thumbs'."
grep -Eq '^MimeType=.+' raw-thumbs.thumbnailer \
  || die "raw-thumbs.thumbnailer : la liste MimeType est vide."
sh -n postinst.sh || die "postinst.sh : erreur de syntaxe."
bash -n build-deb.sh || die "build-deb.sh : erreur de syntaxe."
info "Sources : fichier .thumbnailer en /usr/bin, scripts valides."

if [ -x tests/test-postinst.sh ]; then
  if TEST_OUT="$(tests/test-postinst.sh 2>&1)"; then
    info "Tests du message d'installation : $(printf '%s\n' "$TEST_OUT" | tail -1 | sed 's/^RÉSULTAT : //')"
  else
    printf '%s\n' "$TEST_OUT" | tail -15 | sed 's/^/    | /' >&2
    die "tests/test-postinst.sh a echoue."
  fi
fi

LIBRAW_DEP="$(sed -n 's/^LIBRAW_DEPENDENCY="\(.*\)".*/\1/p' build-deb.sh | head -1)"
[ -n "$LIBRAW_DEP" ] || die "LIBRAW_DEPENDENCY introuvable dans build-deb.sh."

DEB="${PKG}_${VERSION}_amd64.deb"
DEB_SUM="${DEB}.sha256"

# ------------------------------------------------------------
# 2. Mise en coherence (planification)
# ------------------------------------------------------------
step "Mise en coherence des fichiers"

TODAY="$(date +%F)"
export WORK VERSION TODAY

# Prepare dans $WORK la version finale de Cargo.toml et de CHANGELOG.md, ainsi
# que les notes (parties francaise et anglaise). N'ecrit rien dans le depot ;
# affiche la liste des modifications prevues.
plan_files() {
  python3 -I - <<'PY'
import os, re, sys

work = os.environ["WORK"]
version = os.environ["VERSION"]
today = os.environ["TODAY"]
changes = []

def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()

def write(path, text):
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)

# Cargo.toml : version alignee sur VERSION.
cargo = read("Cargo.toml")
cargo_new = re.sub(r'^version = ".*"$', f'version = "{version}"', cargo, count=1, flags=re.M)
if cargo_new != cargo:
    changes.append(f"Cargo.toml : version = {version}")
    write(os.path.join(work, "Cargo.toml.new"), cargo_new)

# CHANGELOG.md : section de la version (existante, ou tiree de [Unreleased]).
text = read("CHANGELOG.md")
sec = re.search(r'^## \[' + re.escape(version) + r'\][^\n]*\n(.*?)(?=^## \[|\Z)', text, flags=re.M | re.S)
if sec:
    body = sec.group(1)
    new_text = text
else:
    unr = re.search(r'^## \[Unreleased\][^\n]*\n(.*?)(?=^## \[|\Z)', text, flags=re.M | re.S)
    if not unr or not unr.group(1).strip():
        sys.stderr.write(
            "\nErreur : CHANGELOG.md ne contient rien a publier. Decrivez les changements sous\n"
            f"« ## [Unreleased] » (ou creez a la main une section « ## [{version}] - date »).\n")
        sys.exit(1)
    body = unr.group(1)
    new_text = (text[:unr.start()]
                + f"## [Unreleased]\n\n## [{version}] - {today}\n\n{body.strip()}\n\n"
                + text[unr.end():])
    changes.append(f"CHANGELOG.md : « [Unreleased] » devient « [{version}] - {today} »")
if not body.strip():
    sys.stderr.write(f"\nErreur : la section [{version}] de CHANGELOG.md est vide.\n")
    sys.exit(1)
write(os.path.join(work, "CHANGELOG.new"), new_text)

# Notes : partie francaise + « ### English summary » facultatif.
en = re.search(r'^### English summary[ \t]*\n(.*?)(?=^### |\Z)', body, flags=re.M | re.S)
if en:
    fr_text = (body[:en.start()] + body[en.end():]).strip()
    en_text = en.group(1).strip()
else:
    fr_text = body.strip()
    en_text = ""
write(os.path.join(work, "notes_fr.md"), fr_text + "\n")
write(os.path.join(work, "notes_en.md"), (en_text + "\n") if en_text else "")

for c in changes:
    print(c)
PY
}

PLANNED="$(plan_files)" || exit 1
if [ -n "$PLANNED" ]; then
  printf '%s\n' "$PLANNED" | sed 's/^/    a modifier : /'
else
  info "Aucune modification de fichier necessaire."
fi
if [ ! -s "$WORK/notes_en.md" ]; then
  info "CHANGELOG : pas de sous-section « ### English summary » pour $VERSION : les notes seront publiees sans resume anglais."
fi

# ------------------------------------------------------------
# Inspection du paquet existant (utilisee avant ET apres reconstruction)
# ------------------------------------------------------------
PROBLEMS=()
inspect_package() {
  PROBLEMS=()
  local d ctl v lock_ver f
  lock_ver="$(awk '/^name = "raw-thumbs"$/ {getline; sub(/^version = "/, ""); sub(/"$/, ""); print; exit}' Cargo.lock)"
  [ "$lock_ver" = "$VERSION" ] || PROBLEMS+=("Cargo.lock : version de raw-thumbs = ${lock_ver:-?} (attendu $VERSION)")

  if [ ! -f "$DEB" ]; then
    PROBLEMS+=("$DEB absent")
    return 0
  fi
  v="$(dpkg-deb -f "$DEB" Version)"
  [ "$v" = "$VERSION" ] || PROBLEMS+=("$DEB : champ Version = $v")
  dpkg-deb -f "$DEB" Maintainer | grep -q 'example.com' && PROBLEMS+=("$DEB : maintainer factice")
  dpkg-deb -f "$DEB" Depends | grep -qF "$LIBRAW_DEP" || PROBLEMS+=("$DEB : dependance $LIBRAW_DEP absente")

  d="$(mktemp -d "$WORK/deb.XXXXXX")"
  dpkg-deb -x "$DEB" "$d"
  ctl="$d.ctl"
  dpkg-deb -e "$DEB" "$ctl"

  [ -x "$d/usr/bin/raw-thumbs" ] || PROBLEMS+=("$DEB : /usr/bin/raw-thumbs absent ou non executable")
  if [ -f target/release/raw-thumbs ] && [ -f "$d/usr/bin/raw-thumbs" ] \
     && ! cmp -s "$d/usr/bin/raw-thumbs" target/release/raw-thumbs; then
    PROBLEMS+=("$DEB : le binaire differe de target/release/raw-thumbs (paquet obsolete)")
  fi
  grep -qx 'Exec=/usr/bin/raw-thumbs %i %o %s' "$d/usr/share/thumbnailers/raw-thumbs.thumbnailer" 2>/dev/null \
    || PROBLEMS+=("$DEB : raw-thumbs.thumbnailer absent ou Exec incorrect")
  cmp -s "$d/usr/share/thumbnailers/raw-thumbs.thumbnailer" raw-thumbs.thumbnailer 2>/dev/null \
    || PROBLEMS+=("$DEB : raw-thumbs.thumbnailer differe de celui du depot")
  if [ -f "$ctl/postinst" ]; then
    cmp -s "$ctl/postinst" postinst.sh || PROBLEMS+=("$DEB : le script d'installation differe de postinst.sh")
  else
    PROBLEMS+=("$DEB : script d'installation (postinst) absent")
  fi
  for f in README.md README.fr.md CHANGELOG.md LICENSE; do
    cmp -s "$d/usr/share/doc/$PKG/$f" "$f" 2>/dev/null \
      || PROBLEMS+=("$DEB : $f absent ou different de celui du depot")
  done
  return 0
}

# Paquet plus ancien que les fichiers qu'il embarque ?
stale_sources() {
  [ -f "$DEB" ] || return 0
  find src Cargo.toml Cargo.lock build-deb.sh postinst.sh raw-thumbs.thumbnailer \
       README.md README.fr.md CHANGELOG.md LICENSE \
       -type f -newer "$DEB" -print -quit 2>/dev/null
}

inspect_package
NEED_REBUILD=false
if [ -n "$PLANNED" ]; then
  NEED_REBUILD=true
  info "Reconstruction necessaire : des fichiers embarques dans le paquet vont changer."
fi
if [ "${#PROBLEMS[@]}" -gt 0 ]; then
  NEED_REBUILD=true
  for p in "${PROBLEMS[@]}"; do info "probleme : $p"; done
fi
s="$(stale_sources)"
if [ -n "$s" ]; then
  NEED_REBUILD=true
  info "$DEB est plus ancien que $s"
fi
$NEED_REBUILD || info "Paquet existant a jour et conforme : il sera publie tel quel."

# ------------------------------------------------------------
# Notes de release
# ------------------------------------------------------------
NOTES="$WORK/notes.md"
{
  printf '# %s %s\n\n' "$PKG" "$VERSION"
  if [ -n "$PREV_TAG" ]; then
    printf '## Nouveautés depuis la %s\n\n' "${PREV_TAG#v}"
  else
    printf '## Première release\n\n'
  fi
  cat "$WORK/notes_fr.md"
  cat <<EOF

## Installation (Ubuntu 26.04)

\`\`\`bash
sudo apt install ./${DEB}
nautilus -q
\`\`\`

Le paquet dépend de \`${LIBRAW_DEP}\` (nom du paquet sur Ubuntu 26.04). Pour les autres distributions, compilez depuis les sources (voir le README).

Vérification du téléchargement :

\`\`\`bash
sha256sum -c ${DEB_SUM}
\`\`\`
EOF
  if [ -s "$WORK/notes_en.md" ]; then
    printf '\n## English summary\n\n'
    cat "$WORK/notes_en.md"
    cat <<EOF

Install on Ubuntu 26.04:

\`\`\`bash
sudo apt install ./${DEB}
nautilus -q
\`\`\`

Verify the download: \`sha256sum -c ${DEB_SUM}\`
EOF
  fi
  cat <<EOF

Voir le [CHANGELOG](https://github.com/${REPO_SLUG}/blob/main/CHANGELOG.md) pour le détail / Full details in the [CHANGELOG](https://github.com/${REPO_SLUG}/blob/main/CHANGELOG.md).
EOF
} > "$NOTES"

step "Notes de release (apercu)"
sed 's/^/    | /' "$NOTES"

# Outils necessaires a la reconstruction : on le verifie AVANT de modifier quoi
# que ce soit, pour ne jamais s'arreter a mi-chemin.
if $NEED_REBUILD; then
  for t in cargo fpm; do
    if ! command -v "$t" >/dev/null 2>&1; then
      if $DRY_RUN; then
        warn "outil manquant pour reconstruire le paquet : $t (necessaire pour la vraie publication)."
      else
        die "outil manquant pour reconstruire le paquet : $t"
      fi
    fi
  done
fi

# ------------------------------------------------------------
# Plan et confirmation
# ------------------------------------------------------------
step "Plan"
info "1. $($NEED_REBUILD && echo 'reconstruire le .deb (build-deb.sh --no-version-change --yes)' || echo 'aucune reconstruction')"
info "2. commit + push de main (etat actuel :)"
git status --short | sed 's/^/         /'
info "3. creer la release $TAG (apres ${PREV_TAG:-aucune release precedente}) sur $REPO_SLUG (stable, 'latest') avec : $DEB, $DEB_SUM"

if $DRY_RUN; then
  printf '\n[dry-run] Rien n'"'"'a ete modifie, committe, pousse ni publie.\n'
  exit 0
fi

if ! $ASSUME_YES; then
  [ -t 0 ] || die "pas de terminal interactif : relancez avec --yes."
  read -r -p $'\nPublier la release '"$TAG"$' ? [o/N] ' a
  [[ "$a" =~ ^[oOyY]$ ]] || { echo "Annule. Rien n'a ete modifie."; exit 0; }
fi

# ------------------------------------------------------------
# 3. Application + reconstruction
# ------------------------------------------------------------
step "Application des modifications"
if [ -n "$PLANNED" ]; then
  [ -f "$WORK/Cargo.toml.new" ] && cp "$WORK/Cargo.toml.new" Cargo.toml
  cmp -s "$WORK/CHANGELOG.new" CHANGELOG.md || cp "$WORK/CHANGELOG.new" CHANGELOG.md
  printf '%s\n' "$PLANNED" | sed 's/^/    modifie : /'
fi

if $NEED_REBUILD; then
  step "Reconstruction du .deb"
  ./build-deb.sh --no-version-change --yes
  [ "$(tr -d '[:space:]' < VERSION)" = "$VERSION" ] || die "VERSION a change pendant le build."
  inspect_package
  if [ "${#PROBLEMS[@]}" -gt 0 ]; then
    for p in "${PROBLEMS[@]}"; do warn "$p"; done
    die "le paquet reconstruit n'est pas conforme : release annulee (rien n'est pousse)."
  fi
  info "Paquet reconstruit et verifie."
fi

sha256sum "$DEB" > "$WORK/$DEB_SUM"

# ------------------------------------------------------------
# 4. Commit + push
# ------------------------------------------------------------
step "Commit et push sur main"
if [ -n "$(git status --porcelain)" ]; then
  git add -A
  git commit -q -m "Release $TAG" -m "Voir CHANGELOG.md."
  info "Commit cree : $(git rev-parse --short HEAD)"
else
  info "Rien a valider."
fi
if [ "$(git rev-list --count origin/main..HEAD)" != "0" ]; then
  git push origin main
fi
SHA="$(git rev-parse HEAD)"
REMOTE_SHA="$(git ls-remote origin refs/heads/main | cut -f1)"
[ "$REMOTE_SHA" = "$SHA" ] || die "origin/main ($REMOTE_SHA) != HEAD local ($SHA) : release annulee."
info "origin/main = $SHA"

# ------------------------------------------------------------
# 5. Release
# ------------------------------------------------------------
step "Creation de la release $TAG"
gh release create "$TAG" "$DEB" "$WORK/$DEB_SUM" \
  --repo "$REPO_SLUG" \
  --target "$SHA" \
  --title "$PKG $VERSION" \
  --notes-file "$NOTES" \
  --latest

git fetch --quiet --tags origin || true

step "Verification"
STATE="$(gh release view "$TAG" --repo "$REPO_SLUG" --json isDraft,isPrerelease,url --jq '"\(.isDraft) \(.isPrerelease) \(.url)"')"
read -r IS_DRAFT IS_PRE URL <<< "$STATE"
if [ "$IS_DRAFT" != "false" ] || [ "$IS_PRE" != "false" ]; then
  die "la release n'est pas une release stable publiee (draft=$IS_DRAFT, prerelease=$IS_PRE)."
fi
ASSETS="$(gh release view "$TAG" --repo "$REPO_SLUG" --json assets --jq '.assets[].name')"
for a in "$DEB" "$DEB_SUM"; do
  printf '%s\n' "$ASSETS" | grep -qxF "$a" || die "fichier absent de la release : $a"
done
echo ""
echo "Release stable publiee : $URL"
printf '%s\n' "$ASSETS" | sed 's/^/   /'
echo ""
echo "Annulation si besoin : gh release delete $TAG --repo $REPO_SLUG --cleanup-tag"
