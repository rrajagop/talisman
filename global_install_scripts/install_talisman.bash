#!/bin/bash
set -euo pipefail
shopt -s extglob

DEBUG=${DEBUG:-''}
FORCE_DOWNLOAD=${FORCE_DOWNLOAD:-''}

# default is a pre-commit hook 
declare HOOK_SCRIPT='pre-commit'  
if [[ $# -gt 0 && $1 =~ pre-push.* ]] ; then    # pre-commit or pre-push has to be the first & only argument to the script
   HOOK_SCRIPT='pre-push'
fi

function run() {
    declare TALISMAN_BINARY_NAME
    
    E_CHECKSUM_MISMATCH=2
    E_UNSUPPORTED_ARCH=5
    
    IFS=$'\n'
    VERSION=${VERSION:-'latest'}
    INSTALL_ORG_REPO=${INSTALL_ORG_REPO:-'thoughtworks/talisman'}
    
    DEFAULT_GLOBAL_TEMPLATE_DIR="$HOME/.git-template"
    TALISMAN_SETUP_DIR=${HOME}/.talisman/bin
    
    TEMP_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'talisman_setup')
    trap "rm -r ${TEMP_DIR}" EXIT
    chmod 0700 ${TEMP_DIR}
    
    function echo_error() {
	echo -ne $(tput setaf 1) >&2
	echo "$1" >&2
	echo -ne $(tput sgr0) >&2
    }
    export -f echo_error
    
    function echo_debug() {
	[[ -z "${DEBUG}" ]] && return
	echo -ne $(tput setaf 3) >&2
	echo "$1" >&2
	echo -ne $(tput sgr0) >&2
    }
    export -f echo_debug
    
    function echo_success {
	echo -ne $(tput setaf 2)
	echo "$1" >&2
	echo -ne $(tput sgr0)
    }
    export -f echo_success
    
    function collect_version_artifact_download_urls() {
	curl --silent "https://api.github.com/repos/${INSTALL_ORG_REPO}/releases/${VERSION}" | \
	    grep -e browser_download_url | grep -o 'https.*' | tr -d '"' > ${TEMP_DIR}/download_urls
	echo_debug "All release artifact download urls can be found at ${TEMP_DIR}/download_urls:"
	[[ -z "${DEBUG}" ]] && return
	cat ${TEMP_DIR}/download_urls
    }
    
    function set_talisman_binary_name() {  # based on OS (linux/darwin) and ARCH(32/64 bit)
	declare ARCHITECTURE
	OS=$(uname -s)
	case $OS in
	    "Linux")
		ARCHITECTURE="linux" ;;
	    "Darwin")
		ARCHITECTURE="darwin" ;;
	    *)
		echo_error "Talisman currently only supports Linux and MacOS(darwin) systems."
		echo_error "If this is a problem for you, please open an issue: https://github.com/thoughtworks/talisman/issues/new"
		exit $E_UNSUPPORTED_ARCH
		;;
	esac
	
	ARCH=$(uname -m)
	case $ARCH in
	    "x86_64")
		ARCHITECTURE="${ARCHITECTURE}_amd64" ;;
	    '^i.?86')
		ARCHITECTURE="${ARCHITECTURE}_386" ;;
	    *)
		echo_error "Talisman currently only supports x86 and x86_64 architectures."
		echo_error "If this is a problem for you, please open an issue: https://github.com/thoughtworks/talisman/issues/new"
		exit $E_UNSUPPORTED_ARCH
		;;
    	esac
	
	TALISMAN_BINARY_NAME="talisman_${ARCHITECTURE}"
    }
    
    function download() {
	OBJECT=$1
	DOWNLOAD_URL=$(grep 'http.*'${OBJECT}'$' ${TEMP_DIR}/download_urls)
	echo_debug "Downloading ${OBJECT} from ${DOWNLOAD_URL}"
	curl --location --silent ${DOWNLOAD_URL} > ${TEMP_DIR}/${OBJECT}
    }
    
    function verify_checksum() {
	FILE_NAME=$1
	CHECKSUM_FILE_NAME='checksums'
	echo_debug "Verifying checksum for ${FILE_NAME}"
	download ${CHECKSUM_FILE_NAME}
	
	pushd ${TEMP_DIR} >/dev/null 2>&1
	grep ${TALISMAN_BINARY_NAME} ${CHECKSUM_FILE_NAME} > ${CHECKSUM_FILE_NAME}.single
	shasum -a 256 -c ${CHECKSUM_FILE_NAME}.single
	popd >/dev/null 2>&1
	echo_debug "Checksum verification successfull!"
	echo
    }
    
    function download_talisman_binary() {
	download ${TALISMAN_BINARY_NAME}
	verify_checksum ${TALISMAN_BINARY_NAME}
    }
    
    function setup_talisman(){
	mkdir -p ${TALISMAN_SETUP_DIR}
	cp ${TEMP_DIR}/${TALISMAN_BINARY_NAME} ${TALISMAN_SETUP_DIR}
	chmod +x ${TALISMAN_SETUP_DIR}/${TALISMAN_BINARY_NAME}
	
	# what's in the talisman hook script (see the comments in the talisman_hook_script.bash file)
	# respects TALISMAN_DEBUG while logging, passes on -d to talisman if TALISMAN_DEBUG is true
	# HOOKNAME =  pre-commit or pre-push based on $0 and/or $1, passed into talisman -githook 
	# respects .talisman_skip and .talisman_skip.<pre-commit/pre-push> to ignore the repo
	cat >${TALISMAN_SETUP_DIR}/talisman_hook_script <<EOF
#!/bin/bash
shopt -s extglob

function echo_debug() {
	MSG="\$@"
	[[ -n "\${TALISMAN_DEBUG}" ]] && echo "\${MSG}"
}

declare HOOKNAME="pre-commit"
NAME=\$(basename \$0)
case "\$NAME" in
	pre-commit*|pre-push*) HOOKNAME="\${NAME}" ;;
	talisman_hook_script)
		if [[ \$# -gt 0 && \$1 =~ pre-push.* ]]; then 
		   HOOKNAME="pre-push"
		fi
		;;
	*)
		echo "Unexpected invocation. Please check invocation name and parameters"
		exit 1
		;;
esac

echo_debug "Firing \${HOOKNAME} hook"

if [[ -f .talisman_skip || -f .talisman_skip.\${HOOKNAME} ]] ; then
	echo_debug "Found skip file. Not performing checks"
	exit 0
fi

DEBUG_OPTS=""
[[ -n "\${TALISMAN_DEBUG}" ]] && DEBUG_OPTS="-d"
CMD="${TALISMAN_SETUP_DIR}/${TALISMAN_BINARY_NAME} \${DEBUG_OPTS} -githook \${HOOKNAME}"
echo_debug "ARGS are \$@"
echo_debug "Executing: \${CMD}"
\${CMD}
EOF

	chmod +x ${TALISMAN_SETUP_DIR}/talisman_hook_script
    }
    
    function setup_git_template_talisman_hook() {
	TEMPLATE_DIR=$(git config --global init.templatedir) || true # find the template_dir if it exists
	
	if [[ "$TEMPLATE_DIR" == "" ]]; then # if no template dir, create one
	    echo "No git template directory is configured. Let's add one."
	    echo "(this will override any system git templates and modify your git config file)"
	    echo
	    read -u1 -p "Git template directory: ($DEFAULT_GLOBAL_TEMPLATE_DIR) " TEMPLATE_DIR
	    echo
	    TEMPLATE_DIR=${TEMPLATE_DIR:-$DEFAULT_GLOBAL_TEMPLATE_DIR}
	    git config --global init.templatedir ${TEMPLATE_DIR}
	else
	    echo "Using existing git template dir: $TEMPLATE_DIR."
	    echo
	fi
	
	# Support '~' in path
	TEMPLATE_DIR=${TEMPLATE_DIR/#\~/$HOME}
	
	if [ -e "${TEMPLATE_DIR}/hooks/${HOOK_SCRIPT}" ]; then
	    # does this handle the case of upgrade - already have the hook installed, but is the old version?
	    if [ "${TALISMAN_SETUP_DIR}/talisman_hook_script" -ef "${TEMPLATE_DIR}/hooks/${HOOK_SCRIPT}" ]; then
		echo_success "Talisman template hook already installed." 
	    else
		echo_error "It looks like you already have a ${HOOK_SCRIPT} hook"
		echo_error "installed at '${TEMPLATE_DIR}/hooks/${HOOK_SCRIPT}'."
		echo_error "If this is a expected, you should consider setting-up a tool"
		echo_error "like pre-commit (brew install pre-commit)"
		echo_error "WARNING! Global talisman hook not installed into git template."
		echo_error "Newly (git-init/git-clone)-ed repositories will not be covered by talisman."
	    fi
	else
	    mkdir -p "$TEMPLATE_DIR/hooks"
	    echo "Setting up template ${HOOK_SCRIPT} hook"
	    ln -svf ${TALISMAN_SETUP_DIR}/talisman_hook_script ${TEMPLATE_DIR}/hooks/${HOOK_SCRIPT}
	    echo_success "Talisman template hook successfully installed."
	fi
    }

    REPO_HOOK_SETUP_SCRIPT_PATH="${TEMP_DIR}/setup_talisman_${HOOK_SCRIPT}_hook_in_repo.bash"
    function write_setup_hook_script() {
	cat >${REPO_HOOK_SETUP_SCRIPT_PATH} <<END_OF_SCRIPT
#!/bin/bash
TALISMAN_PATH="${TALISMAN_SETUP_DIR}/talisman_hook_script"
EXCEPTIONS_FILE=${EXCEPTIONS_FILE}

DOT_GIT_DIR=\$1

function echo_error() {
	echo -ne \$(tput setaf 1) >&2
	echo "\$1" >&2
	echo -ne \$(tput sgr0) >&2
}

function echo_debug() {
	[[ -z "\${DEBUG}" ]] && return
	echo -ne \$(tput setaf 3) >&2
	echo "\$1" >&2
	echo -ne \$(tput sgr0) >&2
}

function echo_success {
	echo -ne \$(tput setaf 2)
	echo "\$1" >&2
	echo -ne \$(tput sgr0)
}

REPO_HOOK_SCRIPT=\${DOT_GIT_DIR}/hooks/${HOOK_SCRIPT}
#check if a hook already exists
if [ -e "\${REPO_HOOK_SCRIPT}" ]; then
	#check if already hooked up to talisman
	if [ "\${REPO_HOOK_SCRIPT}" -ef "\${TALISMAN_PATH}" ]; then
		echo_success "Talisman already setup in \${REPO_HOOK_SCRIPT}"
	else
		if [ -e "\${DOT_GIT_DIR}/../.pre-commit-config.yaml" ]; then
			echo_error "Pre-existing pre-commit.com hook detected in \${DOT_GIT_DIR}/hooks"
		fi
		echo \${DOT_GIT_DIR} | sed 's#/.git\$##' >> ${EXCEPTIONS_FILE}
	fi
else
	echo "Setting up ${HOOK_SCRIPT} hook in \${DOT_GIT_DIR}/hooks"
	mkdir -p \${DOT_GIT_DIR}/hooks || (echo_error "Could not create hooks directory" && return)
	LN_FLAGS="-sf"
	[ -n "$DEBUG" ] && LN_FLAGS="\${LN_FLAGS}v"
	ln \${LN_FLAGS} \${TALISMAN_PATH} \${DOT_GIT_DIR}/hooks/${HOOK_SCRIPT}
	echo_success "DONE"
fi
END_OF_SCRIPT
	chmod +x ${REPO_HOOK_SETUP_SCRIPT_PATH}
	if [[ "${DEBUG}" ]]; then 
	    echo_debug "Contents of repo hook setup script:" && cat ${REPO_HOOK_SETUP_SCRIPT_PATH}
	fi
    }

    function setup_git_talisman_hooks_at(){
	SEARCH_ROOT="$1"
	SEARCH_CMD="find"
	EXTRA_SEARCH_OPTS=""
	echo -e "\tSearching ${SEARCH_ROOT} for git repositories"
	
	SUDO_PREFIX=""
	if [[ "${SEARCH_ROOT}" == "/" ]]; then
	    echo -e "\tPlease enter your password when prompted to enable script to search as root user:"
	    SUDO_PREFIX="sudo"
	    EXTRA_SEARCH_OPTS="-xdev \( -path '/private/var' -prune \) -o"
	fi
	EXCEPTIONS_FILE=${TEMP_DIR}/pre-existing-hooks.paths
	touch ${EXCEPTIONS_FILE}
	
	write_setup_hook_script
	
	CMD_STRING="${SUDO_PREFIX} ${SEARCH_CMD} ${SEARCH_ROOT} ${EXTRA_SEARCH_OPTS} -name .git -type d -exec ${REPO_HOOK_SETUP_SCRIPT_PATH} {} \;"
	echo_debug "EXECUTING: ${CMD_STRING}"
	eval "${CMD_STRING}"
	FULL_TALISMAN_SCRIPT_PATH=${TALISMAN_SETUP_DIR}/talisman_hook_script
	
	NUMBER_OF_EXCEPTION_REPOS=`cat ${EXCEPTIONS_FILE} | wc -l`
	
	if [ ${NUMBER_OF_EXCEPTION_REPOS} -gt 0 ]; then
	    EXCEPTIONS_FILE_HOME_PATH="${HOME}/talisman_missed_repositories.paths"
	    mv ${EXCEPTIONS_FILE} ${EXCEPTIONS_FILE_HOME_PATH}
	    echo_error ""
	    echo_error "Please see ${EXCEPTIONS_FILE_HOME_PATH} for a list of repositories"
	    echo_error "that couldn't automatically be hooked up with talisman as ${HOOK_SCRIPT}"
	    echo_error "You should consider installing a tool like pre-commit (https://pre-commit.com) in those repositories"
	    echo_error "Add the following repo definition into .pre-commit-config.yaml"
	    echo_error "after installing pre-commit in each such repository"
	    tee $HOME/.talisman-precommit-config <<END_OF_SCRIPT
-   repo: local
    hooks:
    -   id: talisman-precommit
        name: talisman
        entry: ${FULL_TALISMAN_SCRIPT_PATH} pre-commit
        language: system
        pass_filenames: false
        types: [text]
        verbose: true
END_OF_SCRIPT
		fi
	}

	set_talisman_binary_name

	# currently doesn't check if the talisman binary and the talisman hook script are upto date
	# would be good to create a separate script which does the upgrade and the initial install 
	if [[ ! -x ${TALISMAN_SETUP_DIR}/${TALISMAN_BINARY_NAME} || ! -x ${TALISMAN_SETUP_DIR}/talisman_hook_script || -n ${FORCE_DOWNLOAD} ]]; then
	    echo "Downloading talisman binary"
	    collect_version_artifact_download_urls
	    download_talisman_binary
	    echo
	    echo "Setting up talisman binary and helper script in $HOME/.talisman"
	    setup_talisman
	fi
	
	echo "Setting up pre-commit hook in git template directory"
	setup_git_template_talisman_hook
	echo
	echo "Setting up talisman hook recursively in git repos"
	read -p "Please enter root directory to search for git repos (Default: ${HOME}): " SEARCH_ROOT
	SEARCH_ROOT=${SEARCH_ROOT:-$HOME}
	setup_git_talisman_hooks_at $SEARCH_ROOT
}

run $0 $@
