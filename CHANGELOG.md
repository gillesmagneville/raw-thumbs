# Changelog

🇫🇷 [Version française](CHANGELOG.fr.md)

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- **`release.sh`**: publishes a GitHub release in one command, on the model of
  nautilus-convert-images (`--dry-run` to see everything without changing
  anything). It checks the repository and the sources, runs
  `tests/test-postinst.sh`, takes the release notes from the CHANGELOG
  ("[Unreleased]" becomes "[X.Y.Z] - date"), rebuilds and inspects the `.deb`,
  then commits, pushes and creates the release with the `.deb` and its
  `.sha256`. See the README.
- Release notes **in English first, then in French** (like the README,
  English by default). They come from the entry of the version in
  `CHANGELOG.md` (English) and in `CHANGELOG.fr.md` (French): `release.sh`
  stops before changing anything if either is missing or empty.
- **Bilingual CHANGELOG**: `CHANGELOG.md` (English, shown by default on
  GitHub) and `CHANGELOG.fr.md` (French), with a link to switch language at
  the top of each file. Both are shipped in the `.deb` package.

## [1.0.2] - 2026-10-29

No change to how thumbnails are generated: this release is about the
messages shown and the documentation.

### Changed

- **Install message in the system language.** The reminder printed when the
  `.deb` is installed (restart Nautilus, clear the thumbnail cache) is shown
  in English, French, Spanish or German depending on the session language
  (gettext rules: `LANGUAGE`, `LC_ALL`, `LC_MESSAGES`, `LANG`), falling back
  to English for any other language. It used to be French only (without
  accents). The Spanish and German texts have not been reviewed by native
  speakers.
- **Diagnostic messages in English.** The messages written to standard error
  (usage, invalid size, libraw, decoding or PNG-writing failures) were in
  French; they are now in English, the language of logs. They are only
  visible when running `raw-thumbs` by hand: Nautilus ignores them.
- **The README shown by default on GitHub is now in English**: `README.md` is
  the English version and the French version becomes `README.fr.md`
  (`README.en.md` disappears). Both are shipped in the `.deb` package.
- **README: License section and mention of Claude's help.** Both READMEs state
  the license (GPL-3.0-only) and specify that the project was built with the
  help of Claude.ai by a non-professional developer, as in
  nautilus-convert-images.

### Added

- `tests/test-postinst.sh`: checks the install message under several `sh`
  interpreters and language settings.

## [1.0.1] - 2026-10-28

### Fixed

- EXIF/MakerNote orientation not applied on the embedded-thumbnail path
  (`libraw_unpack_thumb`/`libraw_dcraw_make_mem_thumb`): photos taken in
  portrait or with the camera rotated appeared rotated by 90°/180°. The full
  decoding path (`dcraw_make_mem_image`) was not affected — libraw already
  applies the rotation internally there. Fixed by reading
  `libraw_image_sizes_t.flip` and applying the matching rotation ourselves,
  only on the embedded thumbnail. Validated on an iPhone DNG (flip=6,
  ColorChecker chart): logo and text upright after the fix, upside down
  before.
- `Cargo.lock`: three checksums (`crc32fast`, `miniz_oxide`, `pkg-config`)
  had been altered since v1.0.0, so that `cargo build` refused to build from
  source ("checksum … changed between lock files"). They are restored to
  their official values, verified against crates.io. To build from source,
  use 1.0.1; the v1.0.0 tag is left as it is.

### Added

- English README (`README.en.md`) and tagline: Ubuntu has had no RAW
  thumbnailer in its repositories since 20.04 LTS.
- `LICENSE` file (GPL-3.0-only, already declared in the package metadata),
  also installed in `/usr/share/doc/raw-thumbs/`.

## [1.0.0] - 2026-08-18

### Changed

- First stable version: renumbering of 0.1.0, whose code is unchanged;
  `MAINTAINER` filled in `build-deb.sh` and `.gitattributes` added.

## [0.1.0] - 2026-08-18

### Added

- RAW thumbnailer for Nautilus / GNOME Files written in Rust, based on
  **libraw** through FFI bindings (`libraw-sys`).
- Embedded-thumbnail extraction (`libraw_unpack_thumb` +
  `libraw_dcraw_make_mem_thumb`): fast path covering the vast majority of
  real RAW files.
- Full RAW decoding as a fallback (`libraw_unpack` + `libraw_dcraw_process` +
  `libraw_dcraw_make_mem_image`) for files with no usable embedded thumbnail.
- Coverage of almost all RAW formats on the market through libraw: Canon
  CR2/CR3/CRW, Nikon NEF/NRW, Sony ARW/SR2/SRF, Fuji RAF, Panasonic RAW/RW2,
  Olympus ORF, Pentax PEF/RAW, Adobe DNG, Sigma X3F, Kodak DCR/K25/KDC,
  Minolta MRW, Hasselblad 3FR, Phase One IIQ, Epson ERF, Mamiya MEF, Leaf
  MOS.
- `raw-thumbs.thumbnailer` registration file compliant with the
  freedesktop.org thumbnailer specification, compatible with the bubblewrap
  sandbox of Nautilus/GNOME Files (installation in `/usr/bin`, the only
  location mounted in the sandbox — `/usr/local` is not).
- `.deb` packaging through `build-deb.sh` (fpm).

### Fixed

- Validated on real RAW files (Sony ARW, Canon CR2): no competing thumbnailer
  registered in `~/.local/share/thumbnailers/` or
  `/usr/local/share/thumbnailers/` must remain active for the same MIME type,
  otherwise a silent failure hides `raw-thumbs`.
