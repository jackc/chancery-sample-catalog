#!/bin/sh
# Fails the build, keeping the previous image, if any tool is missing.
set -eu
for tool in curl dig openssl ssh nc socat pg_dump jq; do
	command -v "$tool"
done
