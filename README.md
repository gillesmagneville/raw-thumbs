# raw-thumbs

🇫🇷 [Version française](README.fr.md)

**Ubuntu has shipped no RAW thumbnailer in its archive since 20.04 LTS**
(the last one, `gnome-raw-thumbnailer`, was in 18.04). raw-thumbs brings
RAW thumbnails back to Nautilus, including for files with no embedded
preview.

RAW thumbnailer for Nautilus / GNOME Files, written in Rust, built on
**libraw** (FFI bindings via `libraw-sys`) to cover nearly all RAW formats
on the market (Canon CR2/CR3/CRW, Nikon NEF/NRW, Sony ARW/SR2, Fuji RAF,
Panasonic RW2, Olympus ORF, Pentax PEF, Adobe DNG, Sigma X3F, Kodak
DCR/KDC, Hasselblad 3FR, Phase One IIQ, etc.).

## Strategy

1. **Embedded thumbnail** (`libraw_unpack_thumb` +
   `libraw_dcraw_make_mem_thumb`): the fast path, which covers the vast
   majority of real-world files.
2. **Full decode** (`libraw_unpack` + `libraw_dcraw_process` +
   `libraw_dcraw_make_mem_image`): automatic fallback for RAW files with
   no usable embedded thumbnail.

In both cases the decoding is done by libraw (a C library, dynamically
linked) — Rust only orchestrates the calls, the resizing (the `image`
crate, Lanczos3 filter) and the PNG output.

## Why not the existing "raw-thumbnailer"?

There is already a project named `raw-thumbnailer` /
`gnome-raw-thumbnailer` (gitlab.gnome.org/World/gnome-raw-thumbnailer,
maintained by the author of libopenraw, packaged on SUSE and the AUR), as
well as a pure-Rust replacement named `miniaturo`. Both rely on
**libopenraw**, whose camera format database has historically been
narrower than **libraw**'s — hence the choice of a different engine and of
a distinct name for this project.

`gnome-raw-thumbnailer` is also no longer in the Ubuntu archive since 20.04
LTS (last version: 18.04, checked with
`rmadison -u ubuntu gnome-raw-thumbnailer`).

## Building & packaging

Build dependencies (Ubuntu 26.04):

```bash
sudo apt install build-essential pkg-config libraw-dev cargo rustc
```

**`.deb` package** (recommended method) — `build-deb.sh` follows the same
principles as the one in [linuxdoctor](https://github.com/gillesmagneville/linuxdoctor)
(and, further on, Planche-Contact): interactive or flag-based versioning,
`VERSION`/`Cargo.toml` updated only after a successful build, staging in a
temporary directory with normalized permissions. It uses
[fpm](https://fpm.readthedocs.io/) — install it with
`gem install --user-install fpm` if missing.

```bash
./build-deb.sh --patch              # or --minor / --major / --no-version-change
./build-deb.sh --patch --yes        # without interactive confirmation
./build-deb.sh --clean              # removes the build folder and generated .deb files
```

Before first use, edit `MAINTAINER` and `URL` at the top of the script —
these are values to customize. The generated package installs the binary
to `/usr/bin/raw-thumbs` and the `raw-thumbs.thumbnailer` file to
`/usr/share/thumbnailers/`, declares a dependency on `libraw23t64` (the
package providing `libraw_r.so` on Ubuntu 26.04 — check this if you build
on another distribution), and prints a reminder to restart Nautilus after
installation (in your system language):

```bash
sudo apt install ./raw-thumbs_<version>_amd64.deb
```

**Build only**, without packaging:

```bash
cargo build --release
```

The resulting binary is `target/release/raw-thumbs` (~750 KB, dynamically
linked to `libraw_r`).

## Manual installation (development only)

To iterate quickly without going through `build-deb.sh` after every
change:

As with any Nautilus thumbnailer, the binary **must** live in a system
location. Beware: that does *not* mean just any system location — Nautilus
runs thumbnailers in a bubblewrap sandbox that only mounts `/usr`, `/lib`,
`/lib64`, `/proc`, `/dev` and the file being processed. **`/usr/local` is
never mounted**: a binary installed there is invisible from inside the
sandbox and fails silently (`execve` → ENOENT), with no visible error on
the user's side — a known GNOME bug, documented since 2018 (Debian
#902288, gnome-desktop#71). So install into `/usr/bin`, not
`/usr/local/bin`:

```bash
sudo cp target/release/raw-thumbs /usr/bin/
sudo cp raw-thumbs.thumbnailer /usr/share/thumbnailers/
killall nautilus
rm -rf ~/.cache/thumbnails/*
```

Then open a folder containing RAW files in Nautilus to check that the
thumbnails appear.

> Installing manually into `/usr/bin` goes against the intended use of the
> FHS (reserved for files managed by the package manager). The clean,
> long-term solution is to package it as a `.deb` (see above), which
> legitimately installs into `/usr/bin` through dpkg.

## Covered MIME types

See `raw-thumbs.thumbnailer` — the list can be extended if a specific RAW
format is not recognized (check the real MIME type with
`file --mime-type my_file.xyz` or `xdg-mime query filetype`).

## Languages

raw-thumbs has no window and no menu of its own: Nautilus simply shows the
thumbnails. The only text meant for a person is the reminder printed when the
`.deb` is installed. It follows your system language — **English, French,
Spanish or German**, and English for any other language (same rules as
`gettext`: the `LANGUAGE`, `LC_ALL`, `LC_MESSAGES` or `LANG` variables).

* The Spanish and German texts have not yet been reviewed by native
  speakers: corrections are welcome.
* The diagnostic messages the program writes on its error output (only
  visible when you run it by hand in a terminal) are in English.
* The "Convert images…" context-menu entry is not part of raw-thumbs: it
  belongs to the separate project nautilus-convert-images, which is
  available in the same four languages.

## Tests

`tests/test-postinst.sh` runs the install script under several shells and
language settings (English, French, Spanish, German, unsupported languages,
variable priority, `LANGUAGE` lists) and checks that it only *prints* the
two commands to run, never executes them.

Validated on a real Nikon NEF, a Canon CR2 and a Sony ARW: embedded
thumbnail extraction takes ~1 s (dominated by libraw's own identification
of the file, not by the Rust code), and the full-decode fallback ~6 s.
Invalid or non-RAW files are handled cleanly (non-zero exit code, no output
file created, no panic).

## License

GPL-3.0-only. See [LICENSE](LICENSE).

raw-thumbs is developed by Gilles MAGNEVILLE. Gilles is not a professional
developer — this project was built with the help of Claude.ai.
