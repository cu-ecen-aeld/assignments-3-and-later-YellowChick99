#!/bin/sh
set -e

conf_dir=/etc/finder-app/conf
result_file=/tmp/assignment4-result.txt

if [ ! -d "$conf_dir" ]; then
  echo "conf directory not found: $conf_dir" >&2
  exit 1
fi

finder "$conf_dir" > "$result_file"
