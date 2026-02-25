#!/bin/sh
set -e

assignment_file="conf/assignment.txt"

if [ ! -f "$assignment_file" ]; then
  echo "assignment file not found: $assignment_file"
  exit 1
fi

assignment=$(cat "$assignment_file" | tr -d '\n')

echo "running assignment: $assignment"

./finder.sh /home "$assignment" 2>/dev/null || true

exit 0
