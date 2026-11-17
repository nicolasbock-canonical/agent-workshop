#!/bin/bash

set -e -u -o pipefail

WORKSHOP_NAME=dev

declare -i debug=0

while (( $# > 0 )); do
    case $1 in
        -h|--help)
            cat <<EOF
Usage: $(basename $0)

-h | --help     This help
-d | --debug    A lot of debugging
EOF
            exit 0
            ;;
        -d|--debug)
            debug=1
            ;;
        *)
            echo "unknown argument '$1'"
            exit 1
            ;;
    esac
    shift
done

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
workshop start ${WORKSHOP_NAME}
