#!/bin/sh

filesdir="$1"
searchstr="$2"

if [ -z "$filesdir" ] || [ -z "$searchstr" ]; then
  echo "Error: missing arguments. Usage: $0 <filesdir> <searchstr>"
  exit 1
fi

if [ ! -d "$filesdir" ]; then
  echo "Error: '$filesdir' is not a directory."
  exit 1
fi

file_count=$(find "$filesdir" -type f | wc -l)
match_lines=$(grep -R -n -- "$searchstr" "$filesdir" 2>/dev/null | wc -l)

echo "The number of files are $file_count and the number of matching lines are $match_lines."
exit 0

