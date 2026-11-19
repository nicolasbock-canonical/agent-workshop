#!/bin/bash

set -e -u -o pipefail

WORKSHOP_NAME=dev

declare -i debug=0
work_dir=""

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

status=$(workshop info | grep '^status:' | awk '{print $2}')
if (( $? != 0 )); then
    workshop launch ${WORKSHOP_NAME}
else
    if [[ ${status} == stopped ]]; then
        workshop start ${WORKSHOP_NAME}
    fi
fi
workshop refresh ${WORKSHOP_NAME}

workshop stop ${WORKSHOP_NAME}
workshop connect ${WORKSHOP_NAME}/setup:ssh-agent
workshop remount ${WORKSHOP_NAME}/opencode:opencode-data ~/.local/share/opencode
workshop remount ${WORKSHOP_NAME}/opencode:opencode-config ~/.config/opencode
if [[ -n ${work_dir} ]]; then
    workshop remount ${WORKSHOP_NAME}/setup:mount "${work_dir}"
fi
workshop start ${WORKSHOP_NAME}
