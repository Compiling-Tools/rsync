# static-rsync

Statically linked rsync binary with proper license compliance (LGPL/GPL),
artifact signing, SBOMs, and reproducible builds.

Found there was no good way to get a static rsync binary for Linux, so I made
one.

## Progress

- [x] Initial recipe (see [`recipe.sh`][recipe])
- [x] Figuring out licenses on all dependencies statically compiled into the binary
- [x] Compliance with license obligations
- [x] SBOM generation (build-time instrumentation, no `apk install`)
- [x] GitHub Artifact Attestations
- [x] Binary signing (GitHub Artifact Attestations)
- [x] Multi-arch builds (Docker images + standalone binaries)
- [x] Auto-update pipeline for new rsync releases
- [x] GitHub Actions workflow

## Download

Every [release][releases] has binaries for `x86_64`, `aarch64`, `armv7`, `x86`,
`riscv64`, `ppc64le` and `s390x`:

```sh
arch=$(uname -m)
curl -fLO https://github.com/Compiling-Tools/rsync/releases/latest/download/rsync-$arch
chmod +x rsync-$arch
```

`uname -m` gives the right name everywhere except 32-bit ARM (use
`arch=armv7`) and 32-bit x86 (use `arch=x86`).

There is also a multi-arch container image with just the binary:

```sh
docker run --rm ghcr.io/compiling-tools/rsync --version
```

Every binary has everything rsync can use except IDN (Unicode host names):
zstd/lz4/zlib compression, xxHash/MD5/SHA checksums via OpenSSL, ACLs and
extended attributes.

### Verifying

Every release file and the container image have GitHub [artifact
attestations][attestations] that prove they were built by this repository's
workflow, and the binaries also have one for their SBOM. Check them with the
[GitHub CLI][gh-cli]:

```sh
gh attestation verify rsync-$arch --repo Compiling-Tools/rsync
gh attestation verify oci://ghcr.io/compiling-tools/rsync:latest --repo Compiling-Tools/rsync
```

`SHA256SUMS` in each release lists the checksums of all its files.

Each binary's SBOM, `rsync-$arch.spdx.json` in the release, names its
components by CPE or purl, so vulnerability scanners can check it, e.g.
`grype sbom:rsync-$arch.spdx.json`.

## How It Works

Builds inside Alpine Linux (musl libc — ideal for static linking). The
libraries rsync links against (acl, OpenSSL's libcrypto, zstd, lz4 and xxHash)
are compiled from the upstream tarballs pinned in [`sources.txt`][sources]
instead of coming from Alpine's `-static` packages, so the exact source of
everything in the binary is known and can be published with it. zlib and popt
come bundled with rsync. rsync is then configured with static flags and
compiled. Result: a single, portable binary with zero runtime dependencies.

| File                  | Purpose                                                                    |
| --------------------- | -------------------------------------------------------------------------- |
| `recipe.sh`           | The whole build. Runs inside Alpine and writes everything to `out/`.       |
| `sources.txt`         | Pinned upstream tarballs: version, SHA-256, URL, CPE and license.          |
| `fetch.sh`            | Downloads the tarballs into `sources/` and checks their SHA-256.           |
| `sbom.sh`             | Writes the SPDX SBOM for the binary; called by `recipe.sh`.                |
| `test.sh`             | Copies files over pipes and through a daemon and checks every attribute.   |
| `update.sh`           | Moves `sources.txt` to the newest rsync release with a valid signature.    |
| `keys/rsync.asc`      | rsync's release signing keys, trusted by `update.sh`.                      |
| `patches/`            | The one change to rsync: the libacl notice in `rsync --version`.           |
| `licenses/`           | License notice for the binary, plus the texts not found in any tarball.    |
| `Dockerfile`          | Runs `recipe.sh` and `test.sh` in a pinned Alpine image.                   |
| `Dockerfile.image`    | Container image made from the already built binaries.                      |
| `.github/workflows/`  | CI, releases and the daily rsync update check.                             |

The linker writes a map of every archive it pulls into the binary, and the
build fails unless exactly the pinned libraries (plus musl and the GCC
runtime) show up in it, so the SBOM and the license notices can't silently
drift from what is actually linked.

## Building

With Docker:

```sh
docker buildx build --output out .
docker buildx build --platform linux/arm64 --output out .   # another architecture (needs QEMU)
```

Or run the recipe and the test directly in any Alpine container:

```sh
docker run --rm -v "$PWD:/src" -w /src alpine:3.24 sh -c './recipe.sh && ./test.sh out/rsync'
```

`test.sh` copies a small tree from rsync to itself, over pipes with every
compression and checksum method and through an rsync daemon, and checks that
contents, permissions, owners, times (after 2038, too), links, special files,
ACLs and extended attributes all arrive intact.

Either way `out/` gets `rsync`, its SBOM `rsync.spdx.json` and `licenses/`.
`fetch.sh` downloads the tarballs into `sources/`, and any later build, Docker
or not, reuses the ones already there.

### Reproducible builds

Two builds of the same commit are bit-for-bit identical, which CI checks on
every run for `x86_64`. To reproduce a release, build its tagged commit with
the commit time as `SOURCE_DATE_EPOCH`:

```sh
SOURCE_DATE_EPOCH=$(git log -1 --format=%ct) docker buildx build \
  --build-arg SOURCE_DATE_EPOCH --platform linux/amd64 --output out .
```

The Alpine image and all sources are pinned. The compiler and other packages
installed during the build are not, because Alpine only keeps the latest build
of each package. So a rebuild long after a release can differ if Alpine has
updated gcc or musl in the meantime; the SBOM records the versions used.

## Maintenance

### One-time setup

1. Under Settings → Actions → General, allow GitHub Actions to create pull
   requests (used by the update workflow).
2. After the first release, make the container image public: new packages on
   ghcr.io are private. Open the `rsync` package from the organization's
   Packages tab, then Package settings → Change visibility → Public. Check it
   with `docker logout ghcr.io && docker pull ghcr.io/compiling-tools/rsync`.

### Releasing

Push a tag named after the rsync version in `sources.txt`, e.g. `v3.5.1`.
To rebuild the same rsync version (say, after a library update), add a
number: `v3.5.1-2`. The workflow builds every architecture, attests and
publishes the binaries, SBOMs, license texts, Corresponding Source and the
container image.

The release stays a draft until everything is uploaded, so if the workflow
fails halfway, fix the cause and re-run it. If the fix needs a commit, move
the tag to it (`git tag -f v3.5.1 && git push -f origin v3.5.1`); the draft is
reused. A published release is never changed; tag a rebuild instead. Only the
newest tag becomes the latest release and the `latest` image; rebuilding an
older version publishes it without moving either.

### Updates

A daily workflow runs `update.sh` and opens a pull request when a new rsync
release is out. `update.sh` only accepts a tarball signed by a key in
`keys/rsync.asc`; if upstream switches keys, check the new key and add it
there. GitHub holds the Build workflow on these pull requests until someone
with write access clicks **Approve workflows to run** in the pull request,
so approve it and wait for the checks before merging. GitHub pauses scheduled
workflows after 60 days without activity in the repository; if that happens,
enable the Update rsync workflow again under Actions.

The other libraries are updated by hand: change the version, SHA-256 and URL
in `sources.txt` after checking the upstream signature, and make sure the
license table in `licenses/README.md` still applies. Dependabot keeps the Alpine
image and the GitHub Actions current.

## Credits

- [RsyncProject/rsync][rsync-up] — the original project
- [jbruechert/rsync-static][rsync-static] — initial inspiration

## License

- **Recipe** (build scripts, Dockerfiles, workflows) — [MIT][license]
- **rsync binary** — GPL-3.0-or-later as a whole; it contains libacl
  (LGPL-2.1-or-later) and permissively licensed libraries. See
  [`licenses/README.md`][licenses] for every component and how the GPL and LGPL
  obligations are met.

Made by [L0RD-ZER0][gh].

[license]: LICENSE
[licenses]: licenses/README.md
[gh]: https://github.com/L0RD-ZER0
[rsync-up]: https://github.com/RsyncProject/rsync
[rsync-static]: https://github.com/jbruechert/rsync-static
[recipe]: recipe.sh
[sources]: sources.txt
[releases]: https://github.com/Compiling-Tools/rsync/releases
[gh-cli]: https://cli.github.com/
[attestations]: https://docs.github.com/en/actions/security-for-github-actions/using-artifact-attestations
