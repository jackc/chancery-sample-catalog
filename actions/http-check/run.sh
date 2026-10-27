#!/bin/sh
# curl uses the proxy variables Chancery sets, so it needs no proxy option.
# Without -L it does not follow redirects, and --proto =https refuses any
# other scheme.
set -u

server=$CHANCERY_CONFIG_SERVER
port=$CHANCERY_CONFIG_PORT
path=$CHANCERY_CONFIG_PATH
expect=$CHANCERY_CONFIG_EXPECT_STATUS

section() {
	printf '\n== %s ==\n' "$1"
}

if [ -z "${HTTPS_PROXY:-}" ]; then
	echo "No egress proxy: $CHANCERY_ACTION has no run destinations." >&2
	echo "Grant it $server port $port under Network access on its settings page:" >&2
	echo "Administration → Action settings → $CHANCERY_ACTION." >&2
	exit 2
fi

case $server in
*:*) url="https://[$server]:$port$path" ;;
*) url="https://$server:$port$path" ;;
esac

# The egress proxy answers 403 for a destination this action is not granted
# and 502 for a granted one the host could not connect to. Each tool reports
# the answer in its own words; proxy_hint explains it, or fails if the log
# holds neither.
proxy_hint() {
	if grep -q -E '(response |reason=|HTTP/1\.[01] )403|CONNECT .*: Forbidden' "$1"; then
		echo "The egress proxy refused: $CHANCERY_ACTION is not granted $server port $port." >&2
		echo "Grant it under Network access: Administration → Action settings → $CHANCERY_ACTION." >&2
	elif grep -q -E '(response |reason=|HTTP/1\.[01] )502|CONNECT .*: Bad Gateway' "$1"; then
		echo "$CHANCERY_ACTION is granted $server port $port, but the Chancery host could not connect to it." >&2
		echo "Check that the server accepts connections on port $port from the Chancery host." >&2
	else
		return 1
	fi
}

format='status=%{http_code}\nversion=%{http_version}\nfirst_byte=%{time_starttransfer}\ntotal=%{time_total}\nbytes=%{size_download}\ntype=%{content_type}\nlocation=%{redirect_url}\n'
errors=$TMPDIR/curl.err
if ! result=$(curl -sS -g --proto =https --max-time 30 -o /dev/null -w "$format" "$url" 2>"$errors"); then
	cat "$errors" >&2
	echo "Could not fetch $url." >&2
	proxy_hint "$errors"
	exit 1
fi

field() {
	printf '%s\n' "$result" | sed -n "s/^$1=//p"
}
status=$(field status)
location=$(field location)

section 'Request'
printf 'GET %s through the egress proxy\n' "$url"

section 'Response'
printf 'Status:       %s (HTTP/%s)\n' "$status" "$(field version)"
printf 'First byte:   %ss\n' "$(field first_byte)"
printf 'Total:        %ss\n' "$(field total)"
printf 'Size:         %s bytes\n' "$(field bytes)"
printf 'Content type: %s\n' "$(field type)"
if [ -n "$location" ]; then
	printf 'Redirects to: %s (not followed)\n' "$location"
fi

section 'Check'
if [ "$status" = "$expect" ]; then
	printf 'OK: status %s, as expected.\n' "$status"
	exit 0
fi
printf 'FAIL: expected status %s, got %s.\n' "$expect" "$status"
if [ -n "$location" ]; then
	echo 'Point the action at the final URL, or expect the redirect status.'
fi
exit 1
