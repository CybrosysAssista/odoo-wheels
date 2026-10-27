#!/bin/bash
# Runs inside the builder image (see Dockerfile). Builds one pinned sdist into a manylinux2014 wheel.
# Usage: build-wheel.sh <distribution> <version> <python, e.g. 3.12> <output dir>
set -euo pipefail

# pip fetches the build tools for each isolated build; ride out flaky connections.
export PIP_RETRIES=10 PIP_TIMEOUT=60

dist=$1 version=$2 python=$3 out=$4
tag=cp${python/./}
py=/opt/python/$tag-$tag/bin/python
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# The sdist straight from PyPI: `pip download --no-binary :all:` would also build the build tools
# (setuptools, Cython) from source, which fails for reasons unrelated to the package.
mkdir "$work/sdist"
url=$("$py" - "$dist" "$version" <<-'EOF'
	import json, sys, urllib.request
	files = json.load(urllib.request.urlopen(f'https://pypi.org/pypi/{sys.argv[1]}/{sys.argv[2]}/json'))['urls']
	print(next(f['url'] for f in files if f['packagetype'] == 'sdist'))
EOF
)
# The image's curl is too old for --retry-all-errors, and --retry skips cut-off transfers.
for attempt in 1 2 3 4 5; do
	curl -fsSL -o "$work/sdist/${url##*/}" "$url" && break
	[ "$attempt" = 5 ] && exit 1
	sleep 10
done
mkdir "$work/src"
case $(ls "$work"/sdist/*) in
	*.zip) unzip -q "$work"/sdist/* -d "$work/src" ;;
	*) tar -xf "$work"/sdist/* -C "$work/src" ;;
esac
src=$(echo "$work"/src/*)

case ${dist,,} in
	python_ldap | python-ldap | pyldap)
		# Link the static OpenLDAP + OpenSSL from the image into _ldap.so and hide their symbols, so the
		# wheel needs no libldap/libssl from the system and can't clash with the ones Python's ssl loads.
		# No SASL: Odoo's auth_ldap only does simple binds.
		"$py" - "$src/setup.cfg" <<-'EOF'
			import configparser, sys
			cfg = configparser.ConfigParser()
			cfg.read(sys.argv[1])
			if not cfg.has_section('_ldap'):
			    cfg.add_section('_ldap')
			cfg['_ldap']['library_dirs'] = '/deps/ldap/lib /deps/ssl/lib'
			cfg['_ldap']['include_dirs'] = '/deps/ldap/include /deps/ssl/include'
			cfg['_ldap']['defines'] = 'HAVE_TLS HAVE_LIBLDAP_R'
			cfg['_ldap']['libs'] = 'ldap lber ssl crypto pthread dl'
			cfg['_ldap']['extra_link_args'] = '-Wl,--exclude-libs,ALL'
			with open(sys.argv[1], 'w') as f:
			    cfg.write(f)
		EOF
		;;
	lxml)
		# Static libxml2/libxslt from the image (only .a files there, so -lxml2 links them in).
		export PATH=/deps/xml/bin:$PATH
		;;
	cbor2)
		export CBOR2_BUILD_C_EXTENSION=1
		;;
esac

# These pinned sdists predate setuptools 81, which dropped pkg_resources (cbor2's setup.py imports it).
echo 'setuptools<81' > "$work/constraints.txt"
PIP_CONSTRAINT="$work/constraints.txt" "$py" -m pip wheel -q --no-deps -w "$work/raw" "$src"
auditwheel repair -w "$out" --plat manylinux2014_x86_64 "$work"/raw/*.whl
