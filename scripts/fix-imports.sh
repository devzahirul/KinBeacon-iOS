#!/bin/bash
# Dev helper: repeatedly builds and demotes `public import X` that the compiler reports as unused publicly.
for i in $(seq 1 30); do
  out=$(scripts/build-package.sh 80)
  line=$(echo "$out" | grep "public import of '" | head -1)
  if [ -z "$line" ]; then echo "$out"; exit 0; fi
  file=$(echo "$line" | cut -d: -f1); mod=$(echo "$line" | sed -E "s/.*public import of '([A-Za-z]+)'.*/\1/")
  sed -i '' "s/^public import $mod\$/import $mod/" "$file"; echo "demoted $mod in $(basename $file)"
done
