# A bare Ubuntu with only the Python interpreter and venv, so any library a wheel doesn't bundle shows up.
# Pythons the release doesn't ship come from the deadsnakes PPA, added by hand: add-apt-repository goes
# through the Launchpad API, which times out often enough to make the matrix flaky.
ARG RELEASE
FROM ubuntu:${RELEASE}
ARG PYTHON
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update -qq \
	&& if ! apt-cache show python${PYTHON}-venv >/dev/null 2>&1; then \
		apt-get install -y -qq curl gpg ca-certificates >/dev/null \
		&& curl -fsSL --retry 5 'https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xF23C5A6CF475977595C89F51BA6932366A755776' \
			| gpg --dearmor -o /usr/share/keyrings/deadsnakes.gpg \
		&& echo "deb [signed-by=/usr/share/keyrings/deadsnakes.gpg] https://ppa.launchpadcontent.net/deadsnakes/ppa/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) main" \
			> /etc/apt/sources.list.d/deadsnakes.list \
		&& apt-get update -qq; \
	fi \
	&& apt-get install -y -qq python${PYTHON} python${PYTHON}-venv >/dev/null \
	&& rm -rf /var/lib/apt/lists/*
