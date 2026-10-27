#!/bin/bash
# Puts rebuilt wheels into a branch's wheel folder in place of the same distribution and version, then
# retags any wheel still named linux_x86_64: auditwheel confirms it only needs glibc/libstdc++ and
# renames it to the manylinux tag it qualifies for, so nothing in the folder is distro-specific.
# Usage: tools/linux/apply.sh <branch wheel folder, e.g. 18.0-py3.12-linux/18.0-py3.12-linux> <built dir from build.sh>
set -euo pipefail

folder=$(cd "$1" && pwd)
built=$(cd "$2" && pwd)

normalize() {
	echo "$1" | tr 'A-Z' 'a-z' | sed -E 's/[-_.]+/_/g'
}

for wheel in "$built"/*.whl; do
	[ -e "$wheel" ] || continue
	name=$(basename "$wheel")
	key="$(normalize "${name%%-*}")-$(echo "$name" | cut -d- -f2)"
	for old in "$folder"/*.whl; do
		old_name=$(basename "$old")
		if [ "$(normalize "${old_name%%-*}")-$(echo "$old_name" | cut -d- -f2)" = "$key" ]; then
			rm "$old"
		fi
	done
	cp "$wheel" "$folder/"
done

leftover=$(cd "$folder" && ls *-linux_x86_64.whl 2>/dev/null || true)
if [ -n "$leftover" ]; then
	docker run --rm -v "$folder:/w" --user "$(id -u):$(id -g)" odoo-wheels-builder bash -c '
		set -euo pipefail
		cd /w
		for wheel in "$@"; do
			mkdir -p /tmp/repaired
			auditwheel repair -w /tmp/repaired "$wheel" >/dev/null 2>&1 || { echo "not portable, rebuild it: $wheel" >&2; exit 1; }
			rm "$wheel"
			mv /tmp/repaired/*.whl .
		done
	' _ $leftover
fi

ls "$folder" | grep -E 'linux_x86_64\.whl$' | grep -vE 'manylinux' && { echo "still distro-specific wheels in $folder" >&2; exit 1; }
true
