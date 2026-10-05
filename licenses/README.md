# Licenses of the static rsync binary

The `rsync` binary is one statically linked program made of the components
below. It is distributed under the GNU General Public License version 3 or
later, rsync's license. The other components are under licenses compatible
with it and keep their own notices.

| Component                            | License                                  | Text                                  |
| ------------------------------------ | ---------------------------------------- | ------------------------------------- |
| rsync                                | GPL-3.0-or-later                         | `rsync.txt`                           |
| popt (bundled with rsync)            | X11                                      | `popt.txt`                            |
| zlib (modified, bundled with rsync)  | Zlib                                     | `zlib.txt`                            |
| libacl                               | LGPL-2.1-or-later                        | `acl.txt`                             |
| libcrypto (OpenSSL 3)                | Apache-2.0                               | `openssl.txt`                         |
| libzstd                              | BSD-3-Clause[^zstd]                      | `zstd.txt`                            |
| liblz4                               | BSD-2-Clause[^lz4]                       | `lz4.txt`                             |
| libxxhash                            | BSD-2-Clause                             | `xxhash.txt`                          |
| musl libc                            | MIT[^musl]                               | `musl.txt`, `musl-arm-memcpy.txt`     |
| GCC runtime[^gcc]                    | GPL-3.0-or-later WITH GCC-exception-3.1  | `gcc-runtime-exception.txt`           |

[^zstd]: Zstandard is dual licensed as BSD-3-Clause or GPL-2.0-only; the
    BSD-3-Clause option is used. Its decoders for pre-1.0 formats, which carry
    notices of their own, are left out of the build.
[^lz4]: Only LZ4's `lib/` directory, which is BSD-2-Clause, is linked. The
    GPL-2.0-or-later command line tool is not.
[^musl]: On 32-bit ARM, musl's `memcpy` is BSD-2-Clause code from Android;
    its notice is in `musl-arm-memcpy.txt`.
[^gcc]: GCC's crtbegin/crtend startup files, and on some architectures parts
    of `libgcc.a`. The GPL version 3 text that the GCC Runtime Library Exception
    refers to is `rsync.txt`.

The exact versions are in each binary's SPDX SBOM and in `sources.txt` in the
source bundle. The build copies every license text out of the source
tarballs, except for musl and the GCC runtime, which come from the Alpine
toolchain and whose texts are kept in this directory.

## Source code

Each release on https://github.com/Compiling-Tools/rsync/releases has the
complete Corresponding Source next to its binaries as
`rsync-static-<version>-source.tar.gz`: the build scripts of this repository
plus every upstream tarball in `sources.txt`, for as long as the binaries are
offered. musl and the GCC runtime are System Libraries of the Alpine build
environment (the GCC runtime is also covered by the GCC Runtime Library
Exception) and are not included; the SBOM records their versions.

## Changes to rsync

rsync's source is modified by one patch, `patches/rsync-libacl-notice.patch`
(2026-10-01), which adds the libacl notice below to `rsync --version` and
`rsync -VV`. Nothing else is changed.

## libacl and the LGPL

This program uses libacl, statically linked, which is covered by the GNU
Lesser General Public License version 2.1 or later. You may modify libacl and
relink rsync against your modified version, and reverse engineer the program
to debug such modifications. The source bundle contains libacl's source and
all of rsync's source and build scripts. To relink, replace the acl tarball in
`sources/`, update its version and SHA-256 in `sources.txt`, and run the build
again. The build installs Alpine's current compiler and musl, which may be
newer than the versions recorded in the SBOM.

## rsync and OpenSSL

rsync's license has an extra permission to link OpenSSL and xxHash
dynamically. This build does not need it: OpenSSL 3 is Apache-2.0 and xxHash
is BSD-2-Clause, both compatible with GPL version 3, so linking them
statically is allowed by the GPL itself.
