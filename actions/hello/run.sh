#!/bin/sh
# Parameters arrive as CHANCERY_PARAM_<NAME>, already validated against
# action.toml. The CHANCERY_ variables below describe the request itself.
set -eu

printf 'Petition %s, requested by %s (%s)\n' \
	"$CHANCERY_PETITION_ID" "$CHANCERY_REQUESTER" "$CHANCERY_REQUESTER_KIND"

i=1
while [ "$i" -le "$CHANCERY_PARAM_COUNT" ]; do
	printf 'Hello, %s! (%d of %d)\n' "$CHANCERY_PARAM_NAME" "$i" "$CHANCERY_PARAM_COUNT"
	if [ "$i" -lt "$CHANCERY_PARAM_COUNT" ]; then
		sleep 1
	fi
	i=$((i + 1))
done

# Standard error is captured too, interleaved with standard output.
echo 'Done.' >&2
