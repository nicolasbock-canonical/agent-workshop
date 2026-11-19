#!/bin/bash

set -e -u -o pipefail

WORKSHOP_NAME=dev

declare -i debug=0
work_dir=""

# Maps "<sdk>:<mount name>" to the host directory it should be backed by.
# The tilde is left unexpanded on purpose; expand_home handles it when used.
declare -A MOUNTS=(
    [copilot:copilot-config]='~/.copilot'
    [gh-cli:gh-config]='~/.config/gh'
    [gh-cli:gh-data]='~/.local/share/gh'
    [neovim:nvim-cache]='~/.cache/nvim'
    [omp:omp-home]='~/.omp'
    [opencode:opencode-config]='~/.config/opencode'
    [opencode:opencode-data]='~/.local/share/opencode'
    [skills:skills]='skills'
)

expand_home() {
    printf '%s' "${1/#\~/${HOME}}"
}

# Succeed when the mount already points at the wanted host directory,
# whether workshop reports it with a literal ~ or an expanded path.
# Relative paths (e.g. "skills") are relative to the current directory;
# workshop reports them as absolute paths, abbreviated with ~ under $HOME.
mount_is_current() {
    local sdk=${1%%:*}
    local mount=${1#*:}
    local wanted=$2
    local current
    current=$(yq ".sdks.\"${sdk}\".mounts.\"${mount}\".\"host-source\"" <<<"${INFO}")

    local expanded
    expanded=$(expand_home "${wanted}")
    if [[ ${expanded} != /* ]]; then
        expanded=$(realpath --canonicalize-missing "${PWD}/${expanded}")
    fi
    local abbreviated=${expanded}
    if [[ ${expanded} == "${HOME}"/* ]]; then
        abbreviated="~/$(realpath --canonicalize-missing --relative-to "${HOME}" "${expanded}")"
    fi
    [[ ${current} == "${wanted}" || ${current} == "${expanded}" || ${current} == "${abbreviated}" ]]
}

while (( $# > 0 )); do
    case $1 in
        -h|--help)
            cat <<EOF
Usage: $(basename $0) [OPTIONS]

-h | --help        This help
-d | --debug       A lot of debugging
-w | --work DIR    Mount host directory DIR at /work in the workshop
EOF
            exit 0
            ;;
        -d|--debug)
            debug=1
            ;;
        -w|--work)
            if (( $# < 2 )); then
                echo "missing argument for '$1'" >&2
                exit 1
            fi
            work_dir=$2
            shift
            ;;
        *)
            echo "unknown argument '$1'" >&2
            exit 1
            ;;
    esac
    shift
done

if [[ -n ${work_dir} ]]; then
    if [[ ! -d ${work_dir} ]]; then
        echo "work directory '${work_dir}' does not exist" >&2
        exit 1
    fi
    work_dir=$(realpath "${work_dir}")
fi

if (( debug != 0 )); then
    set -x
fi

if ! command -v yq >&/dev/null; then
    echo "Installing yq snap on host"
    sudo snap install yq
fi

if ! workshop info ${WORKSHOP_NAME} >&/dev/null; then
    workshop launch ${WORKSHOP_NAME}
else
    status=$(workshop info | yq '.status')
    if [[ ${status} == stopped ]]; then
        workshop start ${WORKSHOP_NAME}
    fi
fi
echo "Refreshing workshop"
workshop refresh ${WORKSHOP_NAME}

if ! workshop connections ${WORKSHOP_NAME} | grep '^ssh-agent' | grep manual >/dev/null; then
    echo "Connecting ssh-agent"
    workshop connect ${WORKSHOP_NAME}/setup:ssh-agent
fi

INFO=$(workshop info ${WORKSHOP_NAME})

declare -a stale=()
for key in "${!MOUNTS[@]}"; do
    if ! mount_is_current "${key}" "${MOUNTS[${key}]}"; then
        stale+=("${key}")
    fi
done
if [[ -n ${work_dir} ]]; then
    work_dir_expanded=$(realpath --canonicalize ${work_dir})
    if ! mount_is_current setup:mount "${work_dir_expanded}"; then
        stale+=("setup:mount")
        MOUNTS[${stale}]="${work_dir_expanded}"
    fi
fi

# The slow stop/start cycle happens once, and only if something is stale.
if (( ${#stale[@]} > 0 )); then
    echo "Remounting host configuration directories"
    workshop stop "${WORKSHOP_NAME}"
    for key in "${stale[@]}"; do
        echo "Remounting ${key} from host"
        host_path=$(expand_home "${MOUNTS[${key}]}")
        mkdir --parents "${host_path}"
        workshop remount "${WORKSHOP_NAME}/${key}" "${host_path}"
    done
    workshop start "${WORKSHOP_NAME}"
fi

# Mounts carry directories only, so ~/.vimrc is copied rather than shared.
# Rerun this script to pick up host edits.
if [[ -f ${HOME}/.vimrc ]]; then
    echo "Copying ~/.vimrc into workshop"
    workshop exec "${WORKSHOP_NAME}" -- bash -c 'cat >~/.vimrc' <"${HOME}/.vimrc"
fi
