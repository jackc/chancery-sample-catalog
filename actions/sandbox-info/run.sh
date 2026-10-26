#!/bin/sh
# Uses only the shell and the utilities in Chancery's minimal base: no df,
# free, nproc or ip, so everything is read from /proc and /sys.
set -u

section() {
	printf '\n== %s ==\n' "$1"
}

section 'Machine'
printf 'Kernel:  %s\n' "$(uname -srm)"
printf 'CPUs:    %s\n' "$(grep -c '^processor' /proc/cpuinfo)"
model=$(grep '^model name' /proc/cpuinfo | head -n 1 | cut -d: -f2- | sed 's/^ *//')
[ -n "$model" ] && printf 'Model:   %s\n' "$model"
mem_kb=$(grep '^MemTotal:' /proc/meminfo | tr -s ' ' | cut -d' ' -f2)
printf 'Memory:  %s MiB\n' "$((mem_kb / 1024))"
printf 'Uptime:  %s seconds (a new machine for every run)\n' "$(cut -d' ' -f1 /proc/uptime)"
printf 'User:    %s\n' "$(id)"

section 'Filesystems'
# Mount point, type and options. A tmpfs shows its size limit in the options.
grep -E '^[^ ]+ (/|/work) ' /proc/mounts | cut -d' ' -f2-4
root_options=$(grep -E '^[^ ]+ / ' /proc/mounts | tail -n 1 | cut -d' ' -f4)
case ",$root_options," in
*,ro,*) echo 'The root filesystem is read-only.' ;;
*) echo 'The root filesystem is writable.' ;;
esac
printf 'Work directory:    %s\n' "$CHANCERY_WORK_DIR"
printf 'Current directory: %s (this action'"'"'s catalog directory)\n' "$(pwd)"
printf 'Artifacts:         %s\n' "$CHANCERY_ARTIFACTS_DIR"

section 'Network'
printf 'Interfaces: %s\n' "$(ls /sys/class/net | tr '\n' ' ')"
if [ -n "${HTTPS_PROXY:-}" ]; then
	printf 'Egress proxy: %s\n' "$HTTPS_PROXY"
	echo 'Only the destinations granted to this action are reachable through it.'
else
	echo 'No egress proxy: this action has no egress grants, so it has no network.'
fi

section 'Limits'
grep -E '^Max (processes|open files)' /proc/self/limits

section 'Environment'
# The environment is built from nothing: nothing leaks in from the host.
env | grep -v '^_=' | sort
