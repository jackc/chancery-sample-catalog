#!/bin/sh
# libpq cannot use an HTTP proxy, so socat listens on a local port and
# forwards each connection through the egress proxy, which resolves the
# server's name; the guest cannot. libpq connects to that port with hostaddr
# and still checks the certificate against host, the server's real name.
# PGPASSWORD comes from the action's secret slot.
set -u

server=$CHANCERY_CONFIG_SERVER
port=$CHANCERY_CONFIG_PORT
database=$CHANCERY_CONFIG_DATABASE
user=$CHANCERY_CONFIG_USER
sslmode=$CHANCERY_CONFIG_SSLMODE
schema_only=${CHANCERY_PARAM_SCHEMA_ONLY:-false}

section() {
	printf '\n== %s ==\n' "$1"
}

if [ -z "${HTTPS_PROXY:-}" ]; then
	echo "No egress proxy: $CHANCERY_ACTION has no run destinations." >&2
	echo "Grant it $server port $port under Network access on its settings page:" >&2
	echo "Administration → Action settings → $CHANCERY_ACTION." >&2
	exit 2
fi
proxy=${HTTPS_PROXY#*://}
proxy=${proxy%/}
proxy_host=${proxy%:*}
proxy_port=${proxy##*:}
target=$server
case $server in
*:*) target="[$server]" ;;
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

# Listeners are read from /proc rather than found by connecting, which would
# open a tunnel to the server. The local port is one nothing listens on yet,
# so the listener that appears is socat's.
listening() {
	grep -q "$(printf ':%04X 00000000:0000 0A' "$1")" /proc/net/tcp
}
local_port=15432
while listening "$local_port"; do
	local_port=$((local_port + 1))
done

# socat's log shows the proxy's answer when it refuses the server.
tunnel_log=$TMPDIR/tunnel.log
socat "TCP-LISTEN:$local_port,bind=127.0.0.1,reuseaddr,fork" \
	"PROXY:$proxy_host:$target:$port,proxyport=$proxy_port" 2>"$tunnel_log" &
tunnel=$!
trap 'kill "$tunnel" 2>/dev/null' EXIT
trap 'exit 1' INT TERM HUP

tries=0
until listening "$local_port"; do
	tries=$((tries + 1))
	if [ "$tries" -gt 50 ] || ! kill -0 "$tunnel" 2>/dev/null; then
		echo "The local tunnel to the egress proxy did not start:" >&2
		cat "$tunnel_log" >&2
		exit 1
	fi
	sleep 0.1
done

conninfo="hostaddr=127.0.0.1 port=$local_port host=$server dbname=$database user=$user sslmode=$sslmode connect_timeout=20 application_name=$CHANCERY_ACTION"
if [ "$sslmode" = verify-full ]; then
	conninfo="$conninfo sslrootcert=system"
fi
set -- --format=custom
if [ "$schema_only" = true ]; then
	set -- "$@" --schema-only
fi
dump=$CHANCERY_ARTIFACTS_DIR/$database.dump

section 'Dump'
printf '%s on %s:%s as %s, sslmode %s\n' "$database" "$server" "$port" "$user" "$sslmode"
errors=$TMPDIR/pg_dump.err
if ! pg_dump "$@" --file="$dump" "$conninfo" 2>"$errors"; then
	rm -f "$dump"
	cat "$errors" >&2
	echo >&2
	printf 'pg_dump could not dump %s from %s:%s. (127.0.0.1 port %s is the local end of the tunnel to it.)\n' "$database" "$server" "$port" "$local_port" >&2
	if proxy_hint "$tunnel_log"; then
		:
	elif grep -q 'certificate verify failed' "$errors"; then
		echo "The server's certificate is not from an authority the system trusts." >&2
		echo "Give the server a public certificate for $server, or make the action with sslmode require." >&2
	elif grep -q 'password authentication failed' "$errors"; then
		echo "Check the password in the action's secret, and that the user may connect from Chancery's address." >&2
	fi
	exit 1
fi
# Warnings, such as a server newer than this client.
cat "$errors" >&2

section 'Artifact'
printf '%s, %s bytes\n' "${dump##*/}" "$(wc -c <"$dump")"
printf 'sha256 %s\n' "$(sha256sum "$dump" | cut -d' ' -f1)"
pg_restore --list "$dump" | sed -n 's/^;[[:space:]]*\(Dumped from database version\|Dumped by pg_dump version\|TOC Entries\):*/\1:/p'
printf 'Restore with: pg_restore --dbname=TARGET %s\n' "${dump##*/}"
