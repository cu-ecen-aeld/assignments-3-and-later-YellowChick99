#!/bin/sh

writefile="$1"
writestr="$2"

# argument check
if [ -z "$writefile" ] || [ -z "$writestr" ]; then
  echo "Error: missing arguments. Usage: $0 <writefile> <writestr>"
  exit 1
fi

# create directory path if not exists
dirpath=$(dirname "$writefile")
mkdir -p "$dirpath" || {
  echo "Error: could not create directory path"
  exit 1
}

# write (overwrite) file
echo "$writestr" > "$writefile" || {
  echo "Error: could not write file"
  exit 1
}

exit 0

