#!/bin/sh
# Point sources.txt at the latest rsync release. The tarball must carry a good
# signature from a key in keys/rsync.asc; if upstream starts signing with a
# new key this fails and the key has to be reviewed and added by hand.
# Prints the new version, or nothing when rsync is already up to date.
set -eu
cd "$(dirname "$0")"

current=$(awk '$1 == "rsync" { print $2 }' sources.txt)
release=$(curl -fsSL https://api.github.com/repos/RsyncProject/rsync/releases/latest)
latest=$(printf '%s\n' "$release" | jq -r .tag_name)
latest=${latest#v}
case $latest in
    '' | *[!0-9.]*) echo "error: unexpected rsync version '$latest'" >&2; exit 1 ;;
esac
# Only ever move forward, e.g. if sources.txt was updated by hand already.
newest=$(printf '%s\n%s\n' "$current" "$latest" | sort -V | tail -n 1)
if [ "$latest" = "$current" ] || [ "$newest" != "$latest" ]; then
    exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
url=https://download.samba.org/pub/rsync/src/rsync-$latest.tar.gz
curl -fsSL -o "$tmp/rsync.tar.gz" "$url"
curl -fsSL -o "$tmp/rsync.tar.gz.asc" "$url.asc"
gpg --dearmor < keys/rsync.asc > "$tmp/keyring.gpg"
gpgv --keyring "$tmp/keyring.gpg" "$tmp/rsync.tar.gz.asc" "$tmp/rsync.tar.gz" >&2

sha256=$(sha256sum "$tmp/rsync.tar.gz" | cut -d' ' -f1)
current_re=$(echo "$current" | sed 's/\./\\./g')
sed -i "/^rsync /{ s/$current_re/$latest/g; s/[0-9a-f]\{64\}/$sha256/; }" sources.txt
echo "$latest"
