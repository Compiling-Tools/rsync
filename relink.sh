#!/bin/sh
set -eu
cd "$(dirname "$0")"
gcc -static -o rsync rsync.o -L. -lacl -llz4 -lzstd -lxxhash -lcrypto
