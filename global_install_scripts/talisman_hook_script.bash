#!/bin/bash
shopt -s extglob

function echo_debug() {
	MSG="$@"
	[[ -n "${TALISMAN_DEBUG}" ]] && echo "${MSG}"
}

declare HOOKNAME="pre-commit"
NAME=$(basename $0)
case "$NAME" in
	pre-commit*|pre-push*) HOOKNAME="${NAME}" ;;
	talisman_hook_script)
		if [[ $# -gt 0 && $1 =~ pre-push.* ]]; then 
		   HOOKNAME="pre-push"
		fi
		;;
	*)
		echo "Unexpected invocation. Please check invocation name and parameters"
		exit 1
		;;
esac

echo_debug "Firing ${HOOKNAME} hook"

if [[ -f .talisman_skip || -f .talisman_skip.${HOOKNAME} ]] ; then
	echo_debug "Found skip file. Not performing checks"
	exit 0
fi

DEBUG_OPTS=""
[[ -n "${TALISMAN_DEBUG}" ]] && DEBUG_OPTS="-d"
CMD="/home/rrajagop/.talisman/bin/talisman_linux_amd64 ${DEBUG_OPTS} -githook ${HOOKNAME}"
echo_debug "ARGS are $@"
echo_debug "Executing: ${CMD}"
${CMD}
