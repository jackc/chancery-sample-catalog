#!/bin/sh
# openssl ignores the proxy variables, so the proxy is passed with -proxy,
# which takes host:port rather than a URL. The proxy resolves the server's
# name; the guest cannot.
set -u

server=$CHANCERY_CONFIG_SERVER
port=$CHANCERY_CONFIG_PORT
warn_days=$CHANCERY_CONFIG_WARN_DAYS

section() {
	printf '\n== %s ==\n' "$1"
}

if [ -z "${HTTPS_PROXY:-}" ]; then
	echo "No egress proxy: $CHANCERY_ACTION has no run destinations." >&2
	echo "Grant it $server port $port under Settings → Run destinations by action." >&2
	exit 2
fi
proxy=${HTTPS_PROXY#*://}
proxy=${proxy%/}

# A hostname is sent as SNI and checked with -checkhost; an IP address is
# checked with -checkip. Options and values are kept in "$@".
case $server in
*:*) connect="[$server]:$port"; set -- -checkip "$server" ;;
*[!0-9.]*) connect="$server:$port"; set -- -checkhost "$server" ;;
*) connect="$server:$port"; set -- -checkip "$server" ;;
esac
sni=
if [ "$1" = -checkhost ]; then
	sni=$server
fi

if ! out=$(openssl s_client -proxy "$proxy" -connect "$connect" ${sni:+-servername "$sni"} </dev/null 2>&1); then
	echo "Could not complete a TLS handshake with $server:$port:" >&2
	printf '%s\n' "$out" | grep -E 'failed|error|errno' | head -n 3 >&2
	echo "If the proxy refused the connection, check that $CHANCERY_ACTION is granted $server port $port." >&2
	exit 1
fi

section 'Connection'
printf '%s:%s through the egress proxy\n' "$server" "$port"
printf '%s\n' "$out" | grep -m 1 'Cipher is' | sed 's/^New, //'

section 'Certificate'
cert=$(printf '%s\n' "$out" | sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p')
printf '%s\n' "$cert" | openssl x509 -noout -subject -issuer -startdate -enddate -ext subjectAltName

section 'Checks'
status=0
verify=$(printf '%s\n' "$out" | grep -m 1 'Verify return code:' | sed 's/^ *//')
printf '%s\n' "$verify"
case $verify in
*'return code: 0 '*) echo 'OK: the chain verifies.' ;;
*) echo 'FAIL: the chain does not verify.'; status=1 ;;
esac
if printf '%s\n' "$cert" | openssl x509 -noout "$@" | grep -q ' does match '; then
	printf 'OK: the certificate names %s.\n' "$server"
else
	printf 'FAIL: the certificate does not name %s.\n' "$server"
	status=1
fi
if printf '%s\n' "$cert" | openssl x509 -noout -checkend $((warn_days * 86400)) >/dev/null; then
	printf 'OK: valid for at least %s more days.\n' "$warn_days"
else
	printf 'FAIL: expires within %s days.\n' "$warn_days"
	status=1
fi
exit $status
