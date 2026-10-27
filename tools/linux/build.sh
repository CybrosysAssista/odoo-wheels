#!/bin/bash
# Rebuilds every wheel in targets.txt as a manylinux2014 wheel, into <out>/<branch>/.
# Usage: tools/linux/build.sh <out dir> [branch filter regex]
# Needs Docker. Each built wheel replaces the same distribution's wheel on that branch.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
out=$(mkdir -p "$1" && cd "$1" && pwd)
filter=${2:-.}

docker build -q -t odoo-wheels-builder "$here" >/dev/null

grep -vE '^\s*(#|$)' "$here/targets.txt" | grep -E "^($filter)" | while read -r branch dist version; do
	python=$(echo "$branch" | grep -oE 'py3\.[0-9]+' | cut -c3-)
	mkdir -p "$out/$branch"
	log="$out/$branch/$dist-$version.log"
	if docker run --rm -v "$out/$branch:/out" odoo-wheels-builder build-wheel.sh "$dist" "$version" "$python" /out >"$log" 2>&1; then
		echo "ok    $branch $dist $version"
		rm -f "$log"
	else
		echo "FAIL  $branch $dist $version (see $log)"
	fi
done
