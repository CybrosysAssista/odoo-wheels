#!/bin/bash
# Checks that the bundled OpenLDAP/OpenSSL in a python-ldap wheel verify server certificates against
# the Ubuntu system trust store, as Odoo's auth_ldap needs for ldaps:// and STARTTLS.
# Usage: tools/linux/verify-ldap-tls.sh <dir holding the branch's .whl files> <python> [ubuntu versions...]
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
wheels=$(cd "$1" && pwd -P)
python=$2
shift 2
status=0

for release in ${*:-22.04 24.04}; do
	image=odoo-wheels-verify:$release-py$python
	docker image inspect "$image" >/dev/null 2>&1 \
		|| docker build -q -t "$image" --build-arg RELEASE="$release" --build-arg PYTHON="$python" -f "$here/verify.Dockerfile" "$here" >/dev/null \
		|| { echo "n/a   ubuntu $release: no python$python package"; continue; }
	if result=$(docker run --rm --hostname ldap.test -v "$wheels:/wheels:ro" "$image" bash -c '
		set -euo pipefail
		python=$1
		apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq slapd openssl ca-certificates >/dev/null 2>&1
		python$python -m venv /venv
		/venv/bin/pip install -q --no-index --find-links /wheels $(ls /wheels/*ldap*.whl) 2>&1 | grep -v pip || true

		# OpenLDAP checks the certificate against the full hostname even when told "localhost",
		# so the server gets a real name (the container hostname, which Docker puts in /etc/hosts).
		mkdir -p /certs && cd /certs
		openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj "/CN=Test CA" -keyout ca.key -out ca.crt 2>/dev/null
		openssl req -newkey rsa:2048 -nodes -subj "/CN=ldap.test" -keyout server.key -out server.csr 2>/dev/null
		printf "subjectAltName=DNS:ldap.test\n" > ext
		openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 2 -extfile ext -out server.crt 2>/dev/null
		chmod 644 server.key
		mkdir -p /slapd.d
		printf "%s\n" "dn: cn=config" "objectClass: olcGlobal" "cn: config" \
			"olcTLSCertificateFile: /certs/server.crt" "olcTLSCertificateKeyFile: /certs/server.key" "" \
			"dn: cn=schema,cn=config" "objectClass: olcSchemaConfig" "cn: schema" > config.ldif
		slapadd -n0 -F /slapd.d -l config.ldif >/dev/null 2>&1
		slapd -F /slapd.d -h "ldap:/// ldaps:///"
		sleep 1

		check() {
			/venv/bin/python - "$1" <<-EOF
				import ldap, sys
				try:
				    for uri, starttls in (("ldaps://ldap.test", False), ("ldap://ldap.test", True)):
				        conn = ldap.initialize(uri)
				        conn.set_option(ldap.OPT_NETWORK_TIMEOUT, 5)
				        if starttls:
				            conn.start_tls_s()
				        conn.simple_bind_s("", "")
				        conn.search_s("", ldap.SCOPE_BASE)
				    outcome = "connects"
				except ldap.LDAPError as e:
				    outcome = f"rejected: {e}"
				print(sys.argv[1], outcome)
			EOF
		}
		# Untrusted CA must be rejected, or the other checks prove nothing.
		# Rejected for the certificate, not for an unreachable server.
		check "untrusted-ca:" | grep -q "certificate verify failed" || { echo "untrusted CA not rejected for its certificate: $(check untrusted-ca:)"; exit 1; }
		cp ca.crt /usr/local/share/ca-certificates/test-ca.crt && update-ca-certificates >/dev/null 2>&1
		check "trusted-ca:" | grep -q connects || { echo "trusted CA rejected (with /etc/ldap/ldap.conf): $(check trusted-ca:)"; exit 1; }
		rm -f /etc/ldap/ldap.conf
		check "trusted-ca-no-ldap.conf:" | grep -q connects || { echo "trusted CA rejected (no ldap.conf, OpenSSL default paths): $(check trusted-ca-no-ldap.conf:)"; exit 1; }
		echo "untrusted CA rejected; ldaps and STARTTLS verify against the system store, with and without /etc/ldap/ldap.conf"
	' _ "$python" 2>&1); then
		echo "ok    ubuntu $release: $(echo "$result" | tail -1)"
	else
		echo "FAIL  ubuntu $release: $(echo "$result" | tail -3)"
		status=1
	fi
done
exit $status
