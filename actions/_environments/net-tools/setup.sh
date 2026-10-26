#!/bin/sh
# The base's apt sources use HTTPS on archive.ubuntu.com and
# security.ubuntu.com, and apt honours the proxy variables Chancery sets.
# A weekly rebuild (refresh = "7d") picks up security updates.
set -eu
export DEBIAN_FRONTEND=noninteractive
apt-get -q update
apt-get -q install -y --no-install-recommends \
	ca-certificates curl bind9-dnsutils openssl openssh-client jq
apt-get clean
rm -rf /var/lib/apt/lists/*
