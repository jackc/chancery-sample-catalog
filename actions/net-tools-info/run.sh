#!/bin/sh
# Some tools print their version on standard error. 2>&1 keeps each version
# on standard output, in order with the rest.
set -u

section() {
	printf '\n== %s ==\n' "$1"
}

section 'System'
. /etc/os-release
printf '%s\n' "$PRETTY_NAME"

section 'Tools'
printf 'curl:    %s\n' "$(curl --version 2>&1 | head -n 1 | cut -d' ' -f1-2)"
printf 'dig:     %s\n' "$(dig -v 2>&1 | head -n 1)"
printf 'openssl: %s\n' "$(openssl version 2>&1)"
printf 'ssh:     %s\n' "$(ssh -V 2>&1)"
printf 'jq:      %s\n' "$(jq --version 2>&1)"

section 'Network'
if [ -n "${HTTPS_PROXY:-}" ]; then
	echo 'This action has run destinations, so an egress proxy is set.'
	exit 0
fi
echo 'No egress proxy: this action has no run destinations.'
echo 'Trying https://example.com anyway:'
if curl -sS --max-time 10 -o /dev/null https://example.com 2>&1; then
	echo 'Reached it, which should not happen without a grant.'
	exit 1
fi
echo 'Unreachable, as expected. Setup destinations apply only to building the image.'
