#!/bin/sh
set -e

testdir="/tmp/aesd-finder-test"
writefile="$testdir/testfile.txt"
writestr="AESD test string"

cd "$(dirname "$0")"

mkdir -p "$testdir"

./writer "$writefile" "$writestr"

if ! grep -q "$writestr" "$writefile"; then
    echo "ERROR: writer did not write expected content"
    exit 1
fi

exit 0

