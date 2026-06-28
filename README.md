# static-rsync

Statically linked rsync binary with proper license compliance (LGPL/GPL),
artifact signing, SBOMs, and reproducible builds.

Found there was no good way to get a static rsync binary for Linux, so I made
one. Work in progress — core recipe works, pipeline still being built.

## Progress

- [x] Initial recipe (see [`recipe.sh`][recipe])
- [ ] Figuring out licenses on all dependencies statically compiled into the binary
- [ ] Compliance with license obligations
- [ ] SBOM generation (build-time instrumentation, no `apk install`)
- [ ] GitHub Artifact Attestations
- [ ] Binary signing (GPG / minisign)
- [ ] Multi-arch builds (Docker images + standalone binaries)
- [ ] Auto-update pipeline for new rsync releases
- [ ] GitHub Actions workflow

## How It Works

Builds inside Alpine Linux (musl libc — ideal for static linking). Static
library packages are installed via `apk`, xxHash is built from source (no
static archive available in Alpine repos), then rsync is configured with
static flags and compiled. Result: a single, portable binary with zero runtime
dependencies.

## Credits

- [RsyncProject/rsync][rsync-up] — the original project
- [jbruechert/rsync-static][rsync-static] — initial inspiration

## License

- **Recipe** (build scripts, Dockerfiles, workflows) — [MIT][license]
- **Rsync** — GPL-3.0-only
- **ACL, Attr** — LGPL-2.1+

Made by [L0RD-ZER0][gh].

[license]: LICENSE
[gh]: https://github.com/L0RD-ZER0
[rsync-up]: https://github.com/RsyncProject/rsync
[rsync-static]: https://github.com/jbruechert/rsync-static
[recipe]: recipe.sh