export CFLAGS="-static"
export LDFLAGS="-static"
export PKG_CONFIG="pkg-config --static"

apk add --no-cache build-base gawk \
    popt-dev popt-static \
    zlib-dev zlib-static \
    zstd-dev zstd-static \
    lz4-dev lz4-static \
    xxhash-dev \
    openssl-dev openssl-libs-static \
    acl-dev acl-static \
    attr-dev attr-static

https://github.com/Cyan4973/xxHash/archive/refs/tags/v0.8.2.tar.gz

tar -xzf v0.8.2.tar.gz
cd xxHash-0.8.2
make -j$(nproc) install

cd -
wget https://github.com/RsyncProject/rsync/releases/download/v3.4.4/rsync-3.4.4.tar.gz
# wget https://github.com/RsyncProject/rsync/releases/download/v3.4.4/rsync-3.4.4.tar.gz.asc
# gpg --verify rsync-3.4.4.tar.gz.asc rsync-3.4.4.tar.gz

cd rsync-3.4.4
mkdir ./dist
cd dist

../configure

make -j$(nproc) LDFLAGS="-static" CFLAGS="-static" PKG_CONFIG="pkg-config --static"

strip rsync
