#!/bin/bash

function run() {
    function echo_error() {
	echo -ne $(tput setaf 1) >&2
	echo "$1" >&2
	echo -ne $(tput sgr0) >&2
    }

    function echo_debug() {
	[[ -z "${DEBUG}" ]] && return
	echo -ne $(tput setaf 3) >&2
	echo "$1" >&2
	echo -ne $(tput sgr0) >&2
    }
    
    function echo_success {
	echo -ne $(tput setaf 2)
	echo "$1" >&2
	echo -ne $(tput sgr0)
    }

    TALISMAN_PATH=$1
    EXCEPTIONS_FILE=$2
    DOT_GIT_DIR=$3
    HOOK_SCRIPT=$4

    REPO_HOOK_SCRIPT=${DOT_GIT_DIR}/hooks/${HOOK_SCRIPT}
    #check if a hook already exists
    if [ -e "${REPO_HOOK_SCRIPT}" ]; then
	#check if already hooked up to talisman
	if [ "${REPO_HOOK_SCRIPT}" -ef "${TALISMAN_PATH}" ]; then
	    rm ${REPO_HOOK_SCRIPT} && echo_success "Removed ${REPO_HOOK_SCRIPT}"
	else
	    if [ -e "${DOT_GIT_DIR}/../.pre-commit-config.yaml" ]; then
		# check if the .pre-commit-config contains "talisman", if so ask them to remove it manually 
		echo_error "Pre-existing pre-commit.com hook detected in ${DOT_GIT_DIR}/hooks"
	    fi
	    echo ${DOT_GIT_DIR} | sed 's#/.git$##' >> EXCEPTIONS_FILE
	fi
    else 
	echo_debug "Didn't find pre-commit hook in ${DOT_GIT_DIR}/hooks, nothing to do"
    fi
}

run $@
