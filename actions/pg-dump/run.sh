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
local_port=15432

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

# socat's log shows the proxy's answer when it refuses the server.
tunnel_log=$TMPDIR/tunnel.log
socat "TCP-LISTEN:$local_port,bind=127.0.0.1,reuseaddr,fork" \
	"PROXY:$proxy_host:$target:$port,proxyport=$proxy_port" 2>"$tunnel_log" &
tunnel=$!
trap 'kill "$tunnel" 2>/dev/null' EXIT

# Wait for the listener in /proc rather than by connecting, which would open
# a tunnel to the server.
listening=$(printf ':%04X 00000000:0000 0A' "$local_port")
tries=0
until grep -q "$listening" /proc/net/tcp; do
	tries=$((tries + 1))
	if [ "$tries" -gt 50 ] || ! kill -0 "$tunnel" 2>/dev/null; then
		echo "The local tunnel to the egress proxy did not start." >&2
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
	if refusal=$(grep -m 1 -o 'CONNECT .*' "$tunnel_log"); then
		printf 'The egress proxy refused it: %s.\n' "$refusal" >&2
		echo "Check that $CHANCERY_ACTION is granted $server port $port under Network access." >&2
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
