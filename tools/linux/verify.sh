#!/bin/bash
# Installs a branch's wheel set into a fresh venv on clean Ubuntu images (no -dev or extra runtime
# libraries) the way the IDE's setup does, then imports every compiled extension module it installed.
# Usage: tools/linux/verify.sh <dir holding the branch's .whl files> <python, e.g. 3.12> [ubuntu versions...]
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
wheels=$(cd "$1" && pwd -P)
python=$2
shift 2
releases=${*:-20.04 22.04 24.04}
status=0

for release in $releases; do
	image=odoo-wheels-verify:$release-py$python
	if ! docker image inspect "$image" >/dev/null 2>&1; then
		if ! docker build -q -t "$image" --build-arg RELEASE="$release" --build-arg PYTHON="$python" -f "$here/verify.Dockerfile" "$here" >/dev/null 2>&1; then
			echo "n/a   ubuntu $release: no python$python package"
			continue
		fi
	fi
	if result=$(docker run --rm -v "$wheels:/wheels:ro" -v "$here/verify-in-container.sh:/verify.sh:ro" "$image" bash /verify.sh "$python" 2>&1); then
		echo "ok    ubuntu $release: $(echo "$result" | tail -1)"
	else
		echo "FAIL  ubuntu $release:"
		echo "$result" | tail -25 | sed 's/^/      /'
		status=1
	fi
done
exit $status
