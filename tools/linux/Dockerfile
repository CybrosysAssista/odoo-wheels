# Builder for the Linux wheel sets.
#
# manylinux2014 (CentOS 7, glibc 2.17) so every wheel runs on any x86_64 distro with glibc >= 2.17
# (Ubuntu 14.04+, Debian 8+, RHEL 7+). This tag is pinned because it is the newest image that still
# ships CPython 3.8 next to 3.10-3.14, which the 12.0-16.0 py3.8 branches need.
FROM quay.io/pypa/manylinux2014_x86_64:2025.06.08-1

# Libraries that auditwheel copies into Pillow and gevent wheels, and the Perl modules OpenSSL's Configure needs.
RUN yum install -y libjpeg-turbo-devel zlib-devel lcms2-devel libxcb-devel freetype-devel libtiff-devel libwebp-devel \
		libffi-devel perl-IPC-Cmd perl-Data-Dumper perl-Time-Piece \
	&& yum clean all

ARG OPENSSL_VERSION=3.5.9
ARG OPENLDAP_VERSION=2.6.16
ARG LIBXML2_VERSION=2.11.9
ARG LIBXSLT_VERSION=1.1.39

WORKDIR /src

# OpenSSL and OpenLDAP are built static and linked into python-ldap's _ldap.so, so the wheel depends
# only on glibc. Paths follow Debian/Ubuntu (the main target), so TLS works with no extra setup there:
# - OpenSSL's default trust store is /etc/ssl/certs (hashed CA directory on Debian, Ubuntu, Arch, SUSE).
# - libldap reads /etc/ldap/ldap.conf, where Ubuntu's libldap-common sets TLS_CACERT.
RUN curl -fsSL https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz | tar xz \
	&& cd openssl-${OPENSSL_VERSION} \
	&& ./Configure linux-x86_64 no-shared no-tests no-docs -fPIC --prefix=/deps/ssl --libdir=lib --openssldir=/etc/ssl \
	&& make -j"$(nproc)" >/dev/null && make install_sw >/dev/null \
	&& cd .. && rm -rf openssl-${OPENSSL_VERSION}

RUN curl -fsSL https://www.openldap.org/software/download/OpenLDAP/openldap-release/openldap-${OPENLDAP_VERSION}.tgz | tar xz \
	&& cd openldap-${OPENLDAP_VERSION} \
	&& CPPFLAGS=-I/deps/ssl/include LDFLAGS=-L/deps/ssl/lib LIBS='-lpthread -ldl' CFLAGS='-O2 -fPIC' \
		./configure --prefix=/deps/ldap --sysconfdir=/etc --with-subdir=ldap --disable-shared --enable-static \
		--disable-slapd --without-cyrus-sasl --with-tls=openssl --without-argon2 \
	&& make -j"$(nproc)" depend >/dev/null && make -j"$(nproc)" -C include >/dev/null \
	&& make -j"$(nproc)" -C libraries >/dev/null && make -C include install >/dev/null && make -C libraries install >/dev/null \
	&& cd .. && rm -rf openldap-${OPENLDAP_VERSION}

# libxml2/libxslt for lxml, static. 2.11 is the newest libxml2 whose API the lxml 4.x sdists still compile against.
RUN curl -fsSL https://download.gnome.org/sources/libxml2/${LIBXML2_VERSION%.*}/libxml2-${LIBXML2_VERSION}.tar.xz | tar xJ \
	&& cd libxml2-${LIBXML2_VERSION} \
	&& CFLAGS='-O2 -fPIC' ./configure --prefix=/deps/xml --disable-shared --enable-static --without-python --without-lzma --without-icu >/dev/null \
	&& make -j"$(nproc)" >/dev/null && make install >/dev/null \
	&& cd .. && rm -rf libxml2-${LIBXML2_VERSION} \
	&& curl -fsSL https://download.gnome.org/sources/libxslt/${LIBXSLT_VERSION%.*}/libxslt-${LIBXSLT_VERSION}.tar.xz | tar xJ \
	&& cd libxslt-${LIBXSLT_VERSION} \
	&& CFLAGS='-O2 -fPIC' ./configure --prefix=/deps/xml --disable-shared --enable-static --without-python --without-crypto \
		--with-libxml-prefix=/deps/xml >/dev/null \
	&& make -j"$(nproc)" >/dev/null && make install >/dev/null \
	&& cd .. && rm -rf libxslt-${LIBXSLT_VERSION}

COPY build-wheel.sh /usr/local/bin/build-wheel.sh
