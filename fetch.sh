#!/bin/sh
# Download every tarball listed in sources.txt into sources/ and check its
# sha256. Files that are already present are only re-checked.
set -eu
cd "$(dirname "$0")"
mkdir -p sources

grep -v '^#' sources.txt | while read -r name version sha256 url _; do
    [ -n "$name" ] || continue
    file="sources/$name-$version.tar.${url##*.}"
    if [ ! -f "$file" ]; then
        wget -q -O "$file.part" "$url"
        mv "$file.part" "$file"
    fi
    echo "$sha256  $file" | sha256sum -c -
done
