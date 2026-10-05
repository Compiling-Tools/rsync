#!/bin/sh
# Build a fully static rsync. Run this inside Alpine Linux, e.g.
#   docker run --rm -v "$PWD:/src" -w /src alpine:3.24 ./recipe.sh
# or use the Dockerfile. Results are written to out/.
set -eux
# An x86 container on a 64-bit kernel (the CI runner) still reports x86_64
# from uname, and OpenSSL would then configure itself for 64-bit code.
if [ "$(apk --print-arch)" = x86 ] && [ "$(uname -m)" = x86_64 ]; then
    exec linux32 "$0" "$@"
fi
cd "$(dirname "$0")"
root=$PWD
prefix=$root/build/prefix
jobs=$(nproc)

# attr-dev only provides a header that acl's build needs; no attr code is
# linked into rsync (musl itself provides the xattr syscalls).
apk add --no-cache build-base perl linux-headers gawk jq attr-dev

./fetch.sh
rm -rf build out
mkdir -p "$prefix/include" "$prefix/lib" out/licenses

export CFLAGS="-O2 -ffile-prefix-map=$root/="
export CPPFLAGS="-I$prefix/include"
export LDFLAGS="-L$prefix/lib"
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(date +%s)}"

# unpack NAME: extract the pinned tarball of NAME into build/NAME and cd there.
unpack() {
    read -r name version _ url _ <<EOF
$(grep "^$1 " "$root/sources.txt")
EOF
    mkdir "$root/build/$name"
    tar -xf "$root/sources/$name-$version.tar.${url##*.}" -C "$root/build/$name" --strip-components=1
    cd "$root/build/$name"
}

unpack xxhash
make -j"$jobs" libxxhash.a
cp libxxhash.a "$prefix/lib/"
cp xxhash.h "$prefix/include/"
cp LICENSE "$root/out/licenses/xxhash.txt"

unpack lz4
make -C lib -j"$jobs" install PREFIX="$prefix" BUILD_SHARED=no
cp lib/LICENSE "$root/out/licenses/lz4.txt"

unpack zstd
# The decoders for zstd's pre-1.0 formats are not needed and come with
# license notices of their own.
make -C lib -j"$jobs" install-static install-includes PREFIX="$prefix" \
    ZSTD_LEGACY_SUPPORT=0
cp LICENSE "$root/out/licenses/zstd.txt"

unpack openssl
# OpenSSL compiles its --prefix into the library, so keep the usual /usr and
# copy the two things rsync needs by hand instead of `make install_dev`.
./Configure --prefix=/usr --openssldir=/etc/ssl \
    no-shared no-module no-apps no-docs no-tests
make -j"$jobs" build_libs
cp libcrypto.a "$prefix/lib/"
cp -r include/openssl "$prefix/include/"
cp LICENSE.txt "$root/out/licenses/openssl.txt"

unpack acl
./configure --prefix="$prefix" --disable-shared --disable-nls
make -j"$jobs" install
cp doc/COPYING.LGPL "$root/out/licenses/acl.txt"

unpack rsync
# Only rsync itself is linked with -static. Given -static in LDFLAGS, OpenSSL's
# Configure turns off PIC and threads, which breaks the static-PIE link on x86.
export LDFLAGS="$LDFLAGS -static"
# LGPL-2.1 section 6: rsync --version prints copyright notices, so libacl's
# notice and a pointer to its license have to be among them.
patch -p1 < "$root/patches/rsync-libacl-notice.patch"
# IDN (Unicode hostnames) would pull in libidn2 and libunistring; skip it.
# --with-openssl-conf=/dev/null stops libcrypto from reading the system's
# openssl.cnf, which may ask for providers this build does not have.
./configure --with-included-popt --with-included-zlib --disable-md2man --disable-idn \
    --with-openssl-conf=/dev/null
# The linker map records which static archives went into the binary.
make -j"$jobs" LDFLAGS="$LDFLAGS -Wl,-Map=rsync.map"
cp COPYING "$root/out/licenses/rsync.txt"
cp popt/COPYING "$root/out/licenses/popt.txt"
cp zlib/README "$root/out/licenses/zlib.txt"

# The SBOM and the license notices list exactly these libraries, so every
# pinned one must be linked in and nothing else may be.
for lib in libxxhash.a liblz4.a libzstd.a libcrypto.a libacl.a; do
    grep -q "/$lib(" rsync.map || { echo "error: $lib is not linked" >&2; exit 1; }
done
# libc.a and libssp_nonshared.a are musl's, libgcc.a is the GCC runtime.
for lib in $(grep -o '[^/]*\.a(' rsync.map | tr -d '(' | sort -u); do
    case $lib in
        libxxhash.a | liblz4.a | libzstd.a | libcrypto.a | libacl.a) ;;
        libc.a | libssp_nonshared.a | libgcc.a) ;;
        *) echo "error: unexpected $lib is linked" >&2; exit 1 ;;
    esac
done
headers=$(readelf -l rsync)
case $headers in
    *INTERP*) echo "error: rsync is dynamically linked" >&2; exit 1 ;;
esac

strip rsync
cp rsync "$root/out/"
cd "$root"
cp licenses/* out/licenses/
./sbom.sh out/rsync > out/rsync.spdx.json
out/rsync --version
