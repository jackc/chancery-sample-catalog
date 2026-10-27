#!/bin/sh
# ssh has no HTTP proxy support of its own, so netcat opens the tunnel
# through the egress proxy, which resolves the server's name; the guest
# cannot. The pinned host key is the only one ssh will accept: -F /dev/null
# and the empty global file keep any other configuration out.
set -u

unit=$1
server=$CHANCERY_CONFIG_SERVER
port=$CHANCERY_CONFIG_PORT
user=$CHANCERY_CONFIG_USER

if [ -z "${HTTPS_PROXY:-}" ]; then
	echo "No egress proxy: $CHANCERY_ACTION has no run destinations." >&2
	echo "Grant it $server port $port under Network access on its settings page:" >&2
	echo "Administration → Action settings → $CHANCERY_ACTION." >&2
	exit 2
fi
proxy=${HTTPS_PROXY#*://}
proxy=${proxy%/}

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

# known_hosts names the server by the action's name, so the entry does not
# depend on how ssh would spell a host and port, and a mismatch is reported
# under the action's name. The working directory is the run's writable
# workspace.
known=$PWD/known_hosts
printf '%s %s\n' "$CHANCERY_ACTION" "$CHANCERY_CONFIG_HOST_KEY" >"$known"

# ssh rejects a key without its final newline ("error in libcrypto"), which a
# key pasted into Administration → Secrets can lose.
key=$SSH_KEY
if [ -n "$(tail -c 1 "$key")" ]; then
	key=$PWD/id_key
	(umask 077 && { cat "$SSH_KEY"; echo; } >"$key")
fi

ssh -F /dev/null -T \
	-o BatchMode=yes \
	-o StrictHostKeyChecking=yes \
	-o HostKeyAlias="$CHANCERY_ACTION" \
	-o UserKnownHostsFile="$known" \
	-o GlobalKnownHostsFile=/dev/null \
	-o IdentitiesOnly=yes \
	-o IdentityFile="$key" \
	-o ConnectTimeout=20 \
	-o ProxyCommand="nc -X connect -x $proxy %h %p" \
	-p "$port" -l "$user" -- "$server" \
	systemctl status --no-pager --lines=20 -- "$unit" 2>"$TMPDIR/ssh.err"
status=$?
cat "$TMPDIR/ssh.err" >&2

# systemctl status exits 3 for a unit that is not running and 4 for one it
# does not know. ssh exits 255 for its own failures.
case $status in
0) ;;
3) printf '\n%s is not running.\n' "$unit" >&2 ;;
4) printf '\n%s has no unit named %s.\n' "$server" "$unit" >&2 ;;
255)
	echo >&2
	echo "ssh could not log in to $user@$server:$port." >&2
	if ! proxy_hint "$TMPDIR/ssh.err" && grep -q 'Host key verification failed' "$TMPDIR/ssh.err"; then
		echo "Check the action's host_key against the server's /etc/ssh/ssh_host_*_key.pub." >&2
	fi
	;;
esac
exit $status
