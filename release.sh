#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

# ============================================================
# raw-thumbs - release.sh
#
# Publishes the stable GitHub release matching the content of VERSION:
#   1. preliminary checks (branch, remote, free tag, sources, tests)
#   2. bringing the files in line (Cargo.toml, CHANGELOG), then rebuilding
#      the package if needed
#   3. checking the content of the .deb
#   4. commit + push to main
#   5. creating the release (tag, notes, .deb, .sha256)
#
# Usual order (VERSION only moves forward through build-deb.sh):
#   ./build-deb.sh --patch --yes     # or --minor / --major
#   ./release.sh --dry-run           # shows everything, changes nothing
#   ./release.sh
#
# The release notes come from the CHANGELOG, in two languages: if the
# section of the version does not exist yet, the content of "## [Unreleased]"
# becomes "## [X.Y.Z] - date", in CHANGELOG.md (English) AND in
# CHANGELOG.fr.md (French). The notes are published in English first (the
# README shows English by default), then in French.
# ============================================================

REPO_SLUG="gillesmagneville/raw-thumbs"
PKG="raw-thumbs"
DRY_RUN=false
ASSUME_YES=false

show_help() {
  cat <<EOF
Usage: ./release.sh [options]

Publishes the stable GitHub release of raw-thumbs (tag v\$(cat VERSION)).
Run it from the root of the repository, after ./build-deb.sh --patch --yes
(or --minor / --major), which advances VERSION.

  --dry-run    Show what would be done (and the release notes) without
               modifying, committing, pushing or publishing anything
  --yes, -y    Do not ask for confirmation
  --help, -h   Show this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --yes|-y) ASSUME_YES=true; shift ;;
    --help|-h) show_help; exit 0 ;;
    *) echo "Unknown option: $1" >&2; show_help >&2; exit 1 ;;
  esac
done

step() { printf '\n>>> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }
die()  { printf '\nError: %s\n' "$*" >&2; exit 1; }

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ------------------------------------------------------------
# 1. Preliminary checks
# ------------------------------------------------------------
step "Preliminary checks"

for t in git gh python3 sha256sum dpkg-deb cmp; do
  command -v "$t" >/dev/null 2>&1 || die "missing tool: $t"
done

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "this folder is not a git repository."
[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || die "the current branch is not 'main'."

ORIGIN_URL="$(git remote get-url origin 2>/dev/null)" || die "no 'origin' remote."
case "$ORIGIN_URL" in
  *"$REPO_SLUG"*) ;;
  *) die "origin does not point to $REPO_SLUG ($ORIGIN_URL)." ;;
esac

if ! gh auth status >/dev/null 2>&1; then
  if $DRY_RUN; then
    warn "gh is not authenticated (run 'gh auth login' before the real publication)."
  else
    die "gh is not authenticated: run 'gh auth login'."
  fi
fi

git fetch --quiet --tags origin || die "git fetch origin failed."
if git rev-parse -q --verify origin/main >/dev/null; then
  BEHIND="$(git rev-list --count HEAD..origin/main)"
  [ "$BEHIND" = "0" ] || die "origin/main has $BEHIND commit(s) missing locally: run 'git pull --rebase' first."
fi

[ -f VERSION ] || die "VERSION file not found."
VERSION="$(tr -d '[:space:]' < VERSION)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "invalid VERSION: '$VERSION' (expected X.Y.Z)."
TAG="v$VERSION"

NEXT_HINT="First run ./build-deb.sh --patch --yes (or --minor / --major) to move to the next version."
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  die "tag $TAG already exists locally: VERSION ($VERSION) is already published. $NEXT_HINT"
fi
if git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
  die "tag $TAG already exists on GitHub: VERSION ($VERSION) is already published. $NEXT_HINT"
fi
if gh release view "$TAG" --repo "$REPO_SLUG" >/dev/null 2>&1; then
  die "a release $TAG already exists on GitHub. $NEXT_HINT"
fi

PREV_TAG="$(git tag -l 'v[0-9]*' --sort=-v:refname | grep -vxF "$TAG" | head -1 || true)"
if [ -n "$PREV_TAG" ]; then
  [ "$(printf '%s\n%s\n' "${PREV_TAG#v}" "$VERSION" | sort -V | tail -1)" = "$VERSION" ] \
    || die "VERSION ($VERSION) is not greater than the latest release ($PREV_TAG)."
  info "Version: $VERSION  ->  tag $TAG  (latest release: $PREV_TAG)"
else
  info "Version: $VERSION  ->  tag $TAG  (first release)"
fi

for f in src/main.rs raw-thumbs.thumbnailer postinst.sh build-deb.sh Cargo.toml Cargo.lock \
         CHANGELOG.md CHANGELOG.fr.md README.md README.fr.md \
         CODE_OF_CONDUCT.md CODE_OF_CONDUCT.fr.md LICENSE; do
  [ -f "$f" ] || die "project file not found: $f"
done

# The .thumbnailer file must point to /usr/bin: Nautilus's bubblewrap
# sandbox never mounts /usr/local (see the README).
grep -qx 'Exec=/usr/bin/raw-thumbs %i %o %s' raw-thumbs.thumbnailer \
  || die "raw-thumbs.thumbnailer: the Exec line must be exactly 'Exec=/usr/bin/raw-thumbs %i %o %s'."
grep -qx 'TryExec=/usr/bin/raw-thumbs' raw-thumbs.thumbnailer \
  || die "raw-thumbs.thumbnailer: the TryExec line must be exactly 'TryExec=/usr/bin/raw-thumbs'."
grep -Eq '^MimeType=.+' raw-thumbs.thumbnailer \
  || die "raw-thumbs.thumbnailer: the MimeType list is empty."
sh -n postinst.sh || die "postinst.sh: syntax error."
bash -n build-deb.sh || die "build-deb.sh: syntax error."
info "Sources: .thumbnailer file pointing to /usr/bin, valid scripts."

if [ -x tests/test-postinst.sh ]; then
  if TEST_OUT="$(tests/test-postinst.sh 2>&1)"; then
    info "Install message tests: $(printf '%s\n' "$TEST_OUT" | tail -1 | sed 's/^RESULT: //')"
  else
    printf '%s\n' "$TEST_OUT" | tail -15 | sed 's/^/    | /' >&2
    die "tests/test-postinst.sh failed."
  fi
fi

LIBRAW_DEP="$(sed -n 's/^LIBRAW_DEPENDENCY="\(.*\)".*/\1/p' build-deb.sh | head -1)"
[ -n "$LIBRAW_DEP" ] || die "LIBRAW_DEPENDENCY not found in build-deb.sh."

DEB="${PKG}_${VERSION}_amd64.deb"
DEB_SUM="${DEB}.sha256"

# ------------------------------------------------------------
# 2. Bringing the files in line (planning)
# ------------------------------------------------------------
step "Bringing the files in line"

TODAY="$(date +%F)"
export WORK VERSION TODAY

# Prepares in $WORK the final version of Cargo.toml and of the two CHANGELOG
# files, as well as the notes (English and French parts). Writes nothing to
# the repository; prints the list of planned changes.
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

# Cargo.toml: version aligned with VERSION.
cargo = read("Cargo.toml")
cargo_new = re.sub(r'^version = ".*"$', f'version = "{version}"', cargo, count=1, flags=re.M)
if cargo_new != cargo:
    changes.append(f"Cargo.toml: version = {version}")
    write(os.path.join(work, "Cargo.toml.new"), cargo_new)

# CHANGELOG.md (English) and CHANGELOG.fr.md (French): section of the version
# (existing, or taken from [Unreleased]). The notes are published in English
# first, then in French: both files must therefore have content.
for path, notes_name in (("CHANGELOG.md", "notes_en.md"), ("CHANGELOG.fr.md", "notes_fr.md")):
    text = read(path)
    sec = re.search(r'^## \[' + re.escape(version) + r'\][^\n]*\n(.*?)(?=^## \[|\Z)', text, flags=re.M | re.S)
    if sec:
        body = sec.group(1)
        new_text = text
    else:
        unr = re.search(r'^## \[Unreleased\][^\n]*\n(.*?)(?=^## \[|\Z)', text, flags=re.M | re.S)
        if not unr or not unr.group(1).strip():
            sys.stderr.write(
                f"\nError: {path} contains nothing to publish. Describe the changes under\n"
                f"\"## [Unreleased]\" (or create a \"## [{version}] - date\" section by hand).\n"
                "The release notes are published in English (CHANGELOG.md) then in French\n"
                "(CHANGELOG.fr.md): both files must be up to date.\n")
            sys.exit(1)
        body = unr.group(1)
        new_text = (text[:unr.start()]
                    + f"## [Unreleased]\n\n## [{version}] - {today}\n\n{body.strip()}\n\n"
                    + text[unr.end():])
        changes.append(f"{path}: \"[Unreleased]\" becomes \"[{version}] - {today}\"")
    if not body.strip():
        sys.stderr.write(f"\nError: the [{version}] section of {path} is empty.\n")
        sys.exit(1)
    write(os.path.join(work, path + ".new"), new_text)
    write(os.path.join(work, notes_name), body.strip() + "\n")

for c in changes:
    print(c)
PY
}

PLANNED="$(plan_files)" || exit 1
if [ -n "$PLANNED" ]; then
  printf '%s\n' "$PLANNED" | sed 's/^/    to change: /'
else
  info "No file change needed."
fi

# ------------------------------------------------------------
# Inspection of the existing package (used BEFORE and AFTER rebuilding)
# ------------------------------------------------------------
PROBLEMS=()
inspect_package() {
  PROBLEMS=()
  local d ctl v lock_ver f
  lock_ver="$(awk '/^name = "raw-thumbs"$/ {getline; sub(/^version = "/, ""); sub(/"$/, ""); print; exit}' Cargo.lock)"
  [ "$lock_ver" = "$VERSION" ] || PROBLEMS+=("Cargo.lock: version of raw-thumbs = ${lock_ver:-?} (expected $VERSION)")

  if [ ! -f "$DEB" ]; then
    PROBLEMS+=("$DEB missing")
    return 0
  fi
  v="$(dpkg-deb -f "$DEB" Version)"
  [ "$v" = "$VERSION" ] || PROBLEMS+=("$DEB: Version field = $v")
  dpkg-deb -f "$DEB" Maintainer | grep -q 'example.com' && PROBLEMS+=("$DEB: placeholder maintainer")
  dpkg-deb -f "$DEB" Depends | grep -qF "$LIBRAW_DEP" || PROBLEMS+=("$DEB: dependency $LIBRAW_DEP missing")

  d="$(mktemp -d "$WORK/deb.XXXXXX")"
  dpkg-deb -x "$DEB" "$d"
  ctl="$d.ctl"
  dpkg-deb -e "$DEB" "$ctl"

  [ -x "$d/usr/bin/raw-thumbs" ] || PROBLEMS+=("$DEB: /usr/bin/raw-thumbs missing or not executable")
  if [ -f target/release/raw-thumbs ] && [ -f "$d/usr/bin/raw-thumbs" ] \
     && ! cmp -s "$d/usr/bin/raw-thumbs" target/release/raw-thumbs; then
    PROBLEMS+=("$DEB: the binary differs from target/release/raw-thumbs (outdated package)")
  fi
  grep -qx 'Exec=/usr/bin/raw-thumbs %i %o %s' "$d/usr/share/thumbnailers/raw-thumbs.thumbnailer" 2>/dev/null \
    || PROBLEMS+=("$DEB: raw-thumbs.thumbnailer missing or wrong Exec line")
  cmp -s "$d/usr/share/thumbnailers/raw-thumbs.thumbnailer" raw-thumbs.thumbnailer 2>/dev/null \
    || PROBLEMS+=("$DEB: raw-thumbs.thumbnailer differs from the repository's")
  if [ -f "$ctl/postinst" ]; then
    cmp -s "$ctl/postinst" postinst.sh || PROBLEMS+=("$DEB: the install script differs from postinst.sh")
  else
    PROBLEMS+=("$DEB: install script (postinst) missing")
  fi
  for f in README.md README.fr.md CHANGELOG.md CHANGELOG.fr.md CODE_OF_CONDUCT.md CODE_OF_CONDUCT.fr.md LICENSE; do
    cmp -s "$d/usr/share/doc/$PKG/$f" "$f" 2>/dev/null \
      || PROBLEMS+=("$DEB: $f missing or different from the repository's")
  done
  return 0
}

# Package older than the files it ships?
stale_sources() {
  [ -f "$DEB" ] || return 0
  find src Cargo.toml Cargo.lock build-deb.sh postinst.sh raw-thumbs.thumbnailer \
       README.md README.fr.md CHANGELOG.md CHANGELOG.fr.md \
       CODE_OF_CONDUCT.md CODE_OF_CONDUCT.fr.md LICENSE \
       -type f -newer "$DEB" -print -quit 2>/dev/null
}

inspect_package
NEED_REBUILD=false
if [ -n "$PLANNED" ]; then
  NEED_REBUILD=true
  info "Rebuild needed: files shipped in the package are going to change."
fi
if [ "${#PROBLEMS[@]}" -gt 0 ]; then
  NEED_REBUILD=true
  for p in "${PROBLEMS[@]}"; do info "problem: $p"; done
fi
s="$(stale_sources)"
if [ -n "$s" ]; then
  NEED_REBUILD=true
  info "$DEB is older than $s"
fi
$NEED_REBUILD || info "Existing package is up to date and compliant: it will be published as is."

# ------------------------------------------------------------
# Release notes
# ------------------------------------------------------------
NOTES="$WORK/notes.md"
{
  # English part first (the README shows English by default), then French.
  printf '# %s %s\n\n' "$PKG" "$VERSION"
  if [ -n "$PREV_TAG" ]; then
    printf "## What's new since %s\n\n" "${PREV_TAG#v}"
  else
    printf '## First release\n\n'
  fi
  cat "$WORK/notes_en.md"
  cat <<EOF

## Installation (Ubuntu 26.04)

\`\`\`bash
sudo apt install ./${DEB}
nautilus -q
\`\`\`

The package depends on \`${LIBRAW_DEP}\` (the package name on Ubuntu 26.04). On other distributions, build from source (see the README).

Verify the download:

\`\`\`bash
sha256sum -c ${DEB_SUM}
\`\`\`

Full details in the [CHANGELOG](https://github.com/${REPO_SLUG}/blob/main/CHANGELOG.md).

---

# Version française

EOF
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

Voir le [CHANGELOG](https://github.com/${REPO_SLUG}/blob/main/CHANGELOG.fr.md) pour le détail.
EOF
} > "$NOTES"

step "Release notes (preview)"
sed 's/^/    | /' "$NOTES"

# Tools needed for the rebuild: checked BEFORE modifying anything, so as
# never to stop halfway.
if $NEED_REBUILD; then
  for t in cargo fpm; do
    if ! command -v "$t" >/dev/null 2>&1; then
      if $DRY_RUN; then
        warn "missing tool to rebuild the package: $t (needed for the real publication)."
      else
        die "missing tool to rebuild the package: $t"
      fi
    fi
  done
fi

# ------------------------------------------------------------
# Plan and confirmation
# ------------------------------------------------------------
step "Plan"
info "1. $($NEED_REBUILD && echo 'rebuild the .deb (build-deb.sh --no-version-change --yes)' || echo 'no rebuild')"
info "2. commit + push of main (current state:)"
git status --short | sed 's/^/         /'
info "3. create release $TAG (after ${PREV_TAG:-no previous release}) on $REPO_SLUG (stable, 'latest') with: $DEB, $DEB_SUM"

if $DRY_RUN; then
  printf '\n[dry-run] Nothing was modified, committed, pushed or published.\n'
  exit 0
fi

if ! $ASSUME_YES; then
  [ -t 0 ] || die "no interactive terminal: run again with --yes."
  read -r -p $'\nPublish release '"$TAG"$'? [y/N] ' a
  [[ "$a" =~ ^[yY]$ ]] || { echo "Cancelled. Nothing was modified."; exit 0; }
fi

# ------------------------------------------------------------
# 3. Applying + rebuilding
# ------------------------------------------------------------
step "Applying the changes"
if [ -n "$PLANNED" ]; then
  [ -f "$WORK/Cargo.toml.new" ] && cp "$WORK/Cargo.toml.new" Cargo.toml
  for cl in CHANGELOG.md CHANGELOG.fr.md; do
    cmp -s "$WORK/$cl.new" "$cl" || cp "$WORK/$cl.new" "$cl"
  done
  printf '%s\n' "$PLANNED" | sed 's/^/    changed: /'
fi

if $NEED_REBUILD; then
  step "Rebuilding the .deb"
  ./build-deb.sh --no-version-change --yes
  [ "$(tr -d '[:space:]' < VERSION)" = "$VERSION" ] || die "VERSION changed during the build."
  inspect_package
  if [ "${#PROBLEMS[@]}" -gt 0 ]; then
    for p in "${PROBLEMS[@]}"; do warn "$p"; done
    die "the rebuilt package is not compliant: release cancelled (nothing is pushed)."
  fi
  info "Package rebuilt and checked."
fi

sha256sum "$DEB" > "$WORK/$DEB_SUM"

# ------------------------------------------------------------
# 4. Commit + push
# ------------------------------------------------------------
step "Commit and push to main"
if [ -n "$(git status --porcelain)" ]; then
  git add -A
  git commit -q -m "Release $TAG" -m "See CHANGELOG.md and CHANGELOG.fr.md."
  info "Commit created: $(git rev-parse --short HEAD)"
else
  info "Nothing to commit."
fi
if [ "$(git rev-list --count origin/main..HEAD)" != "0" ]; then
  git push origin main
fi
SHA="$(git rev-parse HEAD)"
REMOTE_SHA="$(git ls-remote origin refs/heads/main | cut -f1)"
[ "$REMOTE_SHA" = "$SHA" ] || die "origin/main ($REMOTE_SHA) != local HEAD ($SHA): release cancelled."
info "origin/main = $SHA"

# ------------------------------------------------------------
# 5. Release
# ------------------------------------------------------------
step "Creating release $TAG"
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
  die "the release is not a published stable release (draft=$IS_DRAFT, prerelease=$IS_PRE)."
fi
ASSETS="$(gh release view "$TAG" --repo "$REPO_SLUG" --json assets --jq '.assets[].name')"
for a in "$DEB" "$DEB_SUM"; do
  printf '%s\n' "$ASSETS" | grep -qxF "$a" || die "file missing from the release: $a"
done
echo ""
echo "Stable release published: $URL"
printf '%s\n' "$ASSETS" | sed 's/^/   /'
echo ""
echo "To undo if needed: gh release delete $TAG --repo $REPO_SLUG --cleanup-tag"
