# Security Policy

🇫🇷 [Version française](SECURITY.fr.md)

raw-thumbs is maintained by one person, on a voluntary basis. This page explains how to report a security problem and what you can expect in return.

## Supported versions

Only the **latest release** receives security fixes. If you use an older version, please update first: the package is on the [Releases page](https://github.com/gillesmagneville/raw-thumbs/releases) and the changes are listed in the [CHANGELOG](CHANGELOG.md).

## Reporting a vulnerability

**Please do not report a vulnerability in a public issue, pull request or discussion**: anyone could read it before a fix exists.

Report it privately, in one of these two ways:

1. **On GitHub**: open the [Security tab](https://github.com/gillesmagneville/raw-thumbs/security) of the repository and click **Report a vulnerability**. Only you and the maintainer can see the report.
2. **By email**: write to [gilles@magneville.fr](mailto:gilles@magneville.fr) with the subject "raw-thumbs security".

Please include, as far as you can:

- the version of the package (`dpkg -s raw-thumbs`), the version of libraw (`dpkg -l 'libraw*'`) and your distribution;
- a description of the problem and the steps to reproduce it;
- what you think the impact is;
- if the problem comes from a particular file, the file itself — only if you may share it.

## What to expect

These are goals, not guarantees, since there is only one maintainer:

- an acknowledgement of your report within **7 days**;
- an answer on whether it is considered a vulnerability, then news at least every few weeks until it is settled;
- a fix published in a **new release**, mentioned in the CHANGELOG; for a serious problem, a GitHub security advisory too;
- you are credited in the release notes, unless you prefer to stay anonymous.

Please keep the details private until a fixed version is available, so that users have the time to update.

## What is covered

raw-thumbs has no window, works on your computer and does not use the network. What makes it sensitive is that **Nautilus launches it by itself on every RAW file shown in a folder**, without you opening the file: a file received by email or downloaded is enough. Nautilus runs thumbnailers in a sandbox, which limits the consequences of a flaw, but does not make a report less useful. A report is relevant, for example, if:

- a RAW file (or any file given a RAW type) makes raw-thumbs crash in an exploitable way, run code, or read or write anything other than the thumbnail it has to produce;
- the `.deb` package, its installation script, the `.thumbnailer` file or the release scripts can be abused;
- a file of a release does not match its published `.sha256` fingerprint.

## What is not covered

- A vulnerability in **libraw** itself: this C library is not part of raw-thumbs, it comes from your distribution (package `libraw23t64`). Please report it to the LibRaw project and to your distribution; updating that package is enough. Do tell me if raw-thumbs needs a change as well.
- A vulnerability in the **`image` Rust library**, which is built into the program: please report it to that project, and tell me as well, since the fix needs a new release of raw-thumbs.
- A vulnerability in **Nautilus, GNOME or the way thumbnailers are launched** (including their sandbox): please report it to the project or the distribution concerned.
- Problems that need a computer which is already compromised, or physical access to it.
- Ordinary bugs without security consequences (a thumbnail that does not appear, for example): please open an [issue](https://github.com/gillesmagneville/raw-thumbs/issues) instead.

## Checking what you download

Download the package only from the [Releases page](https://github.com/gillesmagneville/raw-thumbs/releases) of this repository. It is published with its `.sha256` file. To check a download, put the package and its `.sha256` file in the same folder:

```bash
sha256sum -c raw-thumbs_X.Y.Z_amd64.deb.sha256
```
