#!/bin/sh
# Smoke test for a built rsync: copy a small tree with ACLs, extended
# attributes, links, a FIFO, owners, special permissions and a post-2038
# timestamp, over a pipe with every compression and checksum method and
# through an rsync daemon, and check that all of it arrives intact. Runs as
# root inside Alpine Linux, like recipe.sh:
#   ./test.sh out/rsync
set -eux
rsync=$(realpath "$1")

apk add --no-cache acl attr

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"

mkdir src src/dir
echo hello > src/file
seq 100000 > src/big
ln src/file src/hardlink
ln -s file src/symlink
mkfifo src/fifo
chmod 640 src/file
chmod 2750 src/dir
chown 1234:5678 src/big
setfacl -m u:1234:rw src/file
setfattr -n user.test -v value src/file
# A time other than now, so rsync really has to set it on everything, and
# after 2038 to catch 32-bit time_t problems.
find src -exec touch -h -d '2040-01-02 03:04:05' {} +

# snapshot DIR: print the metadata of everything in DIR that rsync -aHAX
# should preserve.
snapshot() {
    (
        cd "$1"
        find . -exec stat -c '%N %A %u %g %h %y' {} + | sort
        find . ! -type l | sort | while read -r f; do
            getfacl -p "$f"
            getfattr -d "$f"
        done
    )
}
snapshot src > expected

# check SOURCE OPTION...: copy SOURCE into dst and compare dst with src.
# --timeout makes a stalled transfer fail instead of hanging the build.
check() {
    source=$1
    shift
    "$rsync" -aHAX --timeout=120 "$@" "$source" dst/
    diff -r src dst
    snapshot dst > actual
    diff expected actual
}

"$rsync" --version

# A fake remote shell: it is called as `rsh localhost rsync --server ...`,
# drops the host name and "rsync", and runs the rsync under test instead. So
# rsync talks to itself over pipes the same way it does over SSH.
printf '#!/bin/sh\nshift 2\nexec "%s" "$@"\n' "$rsync" > rsh
chmod +x rsh
export RSYNC_RSH="$tmp/rsh"
for method in zstd lz4 zlibx zlib none; do
    rm -rf dst
    check localhost:src/ --compress --compress-choice="$method"
done
# After each copy, change a few bytes without changing the size or the time:
# only --checksum notices, and the update goes through rsync's delta transfer.
for method in xxh128 xxh3 xxh64 md5 md4 sha1; do
    rm -rf dst
    check localhost:src/ --checksum --checksum-choice="$method"
    printf XXXX | dd of=dst/big bs=1 seek=1000 conv=notrunc
    touch -d '2040-01-02 03:04:05' dst/big
    check localhost:src/ --checksum --checksum-choice="$method"
done

# An rsync daemon on localhost, with a password to exercise its auth digests.
cat > rsyncd.conf <<EOF
use chroot = no
[src]
    path = $tmp/src
    uid = 0
    gid = 0
    auth users = tester
    secrets file = $tmp/secrets
EOF
echo tester:secret > secrets
chmod 600 secrets
"$rsync" --daemon --no-detach --address=127.0.0.1 --port=8730 --config=rsyncd.conf &
daemon=$!
trap 'kill "$daemon"; rm -rf "$tmp"' EXIT
export RSYNC_PASSWORD=secret
# Give the daemon up to 30 tries to start listening; it is slow under QEMU.
for _ in $(seq 30); do
    "$rsync" --timeout=5 rsync://127.0.0.1:8730/ > /dev/null 2>&1 && break
    sleep 1
done
# Fails if the daemon died, e.g. because something else holds the port.
kill -0 "$daemon"
rm -rf dst
check rsync://tester@127.0.0.1:8730/src/
