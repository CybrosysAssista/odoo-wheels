# Linux wheel tooling

Every wheel on a `*-linux` branch must be a **manylinux** wheel: it may depend only on glibc (2.17 or
newer) and the few libraries every distro has, with anything else bundled inside it. A wheel built on
one Ubuntu release and linked to that release's libraries (`libldap-2.5.so.0`, `libldap.so.2`,
`libjpeg.so.8`, a newer glibc, …) installs fine everywhere but fails at import time on other releases.

## Files

| File | Purpose |
|---|---|
| `targets.txt` | Wheels rebuilt from source because PyPI has no manylinux wheel for that exact version and Python. |
| `Dockerfile` | Builder: manylinux2014 (glibc 2.17, CPython 3.8–3.14) plus static OpenSSL, OpenLDAP, libxml2, libxslt. |
| `build-wheel.sh` | Runs in the builder: one pinned sdist → `auditwheel repair` → manylinux2014 wheel. |
| `build.sh` | Builds every target (or those matching a branch regex) into `<out>/<branch>/`. |
| `apply.sh` | Swaps built wheels into a branch's wheel folder and retags any remaining `linux_x86_64` wheel. |
| `verify.sh` | Installs a branch's set the way the IDE does, on bare Ubuntu images, and imports every compiled module. |
| `verify-ldap-tls.sh` | Starts slapd and checks python-ldap's LDAPS/STARTTLS certificate checks against the system trust store. |

## Rebuilding a branch

```bash
tools/linux/build.sh /tmp/built '18.0-py3.12-linux'
git worktree add /tmp/wt 18.0-py3.12-linux
tools/linux/apply.sh /tmp/wt/18.0-py3.12-linux /tmp/built/18.0-py3.12-linux
tools/linux/verify.sh /tmp/wt/18.0-py3.12-linux 3.12 20.04 22.04 24.04 25.10 26.04
tools/linux/verify-ldap-tls.sh /tmp/wt/18.0-py3.12-linux 3.12 22.04 24.04 26.04
```

Adding a wheel to a branch: prefer the manylinux wheel from PyPI. If PyPI has none for that version and
Python, add a line to `targets.txt` and build it here; never commit a wheel built on a workstation.

## python-ldap

OpenSSL and OpenLDAP are linked statically into `_ldap.so` with their symbols hidden, so the wheel needs
no `libldap`/`libssl` from the system. Their paths follow Debian/Ubuntu: OpenSSL trusts `/etc/ssl/certs`
and libldap reads `/etc/ldap/ldap.conf`. On Fedora/RHEL, LDAPS needs `TLS_CACERT` set in `ldap.conf` or
`LDAPTLS_CACERT`. Rebuild these wheels after an OpenSSL security release (`OPENSSL_VERSION` in `Dockerfile`).
