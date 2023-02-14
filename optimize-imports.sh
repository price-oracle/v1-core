#!/bin/sh

# This script tries to remove imports one by one while making sure that the
# project can still be compiled, so that the minimum number of imports is used.
# This approach is really inefficient, but good enough given that it can just
# be run once in a while to unclutter imports.
# source modified from https://github.com/ChainSecurity/trimport

set -e
set -u

compile(){
  echo Compiling...
  forge build >/dev/null 2>&1
}

echo "This script will run on the following files:"
find 'solidity' -type f \( -iname '*.sol' ! -iname "*.t.*" \)
echo "Continue? [y/N]"

read -r answer
if [ "$answer" != "y" ]; then
  exit 2
fi


echo "Compiling once with original files as a sanity check"
compile || exit 3

tmp="$(mktemp)"

find 'solidity' -type f \( -iname '*.sol' ! -iname "*.t.*" \) |\
while read -r f ; do
  grep -n '^ *import' "$f" | cut -d':' -f1 |\
    while read -r line; do
      cp "$f" "$tmp"
      sed -in-place "$line"'s/.*//' "$f"
      compile || cp "$tmp" "$f"
    done
done

find . -name "*.soln-place" -type f -delete
yarn lint:fix

exit 0

