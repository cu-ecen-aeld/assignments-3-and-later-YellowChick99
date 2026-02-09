set -e

make clean

make

testdir="/tmp/aesd-finder-test"
writefile="$testdir/testfile.txt"
writestr="AESD test string"

mkdir -p "$testdir"

./writer "$writefile" "$writestr"

if ! grep -q "$writestr" "$writefile"; then
    echo "ERROR: writer did not write expected content"
    exit 1
fi

exit 0

