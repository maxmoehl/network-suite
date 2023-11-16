#!/bin/sh -e

HOST_PREFIX="nsh-"
NETWORK_PREFIX="nsn-"

Dump=0
Force=0

__error() {
	echo "error: ${*}" > /dev/stderr
	return 1
}

# shift can exit with a non-zero code if there are no more arguments, we
# don't want that.
alias __shift='test "${#}" -gt 0 && shift'
alias __strip_prefix='sed -E "s/(${HOST_PREFIX})|(${NETWORK_PREFIX})//g"'

# Usage: __validate NAME
__validate() {
	# reserved names
	if [ "${1}" = "lo" ]; then __error "'lo' is a reserved name"; fi
	if [ "${1}" = "br0" ]; then __error "'br0' is a reserved name"; fi

	# must be a valid device name
	if ! expr "${1}" : "^[a-zA-Z0-9_-]\{2,15\}$" > /dev/null; then __error "'${1}' is not a valid name"; fi
}

# Execute ip command or dump it to stdout.
__ip() {
	if [ "${Dump}" -eq 1 ]; then
		echo "ip ${*}"
	else
		ip "${@}"
	fi
}

# Usage: __host_exec NAME COMMAND ARGS...
__host_exec() {
	_host_name="${HOST_PREFIX}${1:?error: NAME is empty}"; __validate "${_host_name}"
	__shift

	if [ "${#}" -eq 0 ]; then __error "COMMAND is empty"; fi

	__ip netns exec "${_host_name}" "${@}"
}

# Usage: __host_add NAME
__host_add() {
	_host_name="${HOST_PREFIX}${1:?error: NAME is empty}"; __validate "${_host_name}"

	__ip netns add "${_host_name}"
	__ip -n "${_host_name}" link set lo up
}

__host_list() {
	if [ "$(id -u)" -ne 0 ]; then
		ip netns show | grep "^${HOST_PREFIX}" | __strip_prefix | sort
	else
		ip netns show | grep "^${HOST_PREFIX}" | sort | while read -r _host_name; do
			echo "$(echo "${_host_name}" | __strip_prefix) ($(ip -o -n "${_host_name}" link show | grep -oP '[a-zA-Z0-9]+(?=@[a-zA-Z0-9]+)' | sort | xargs))"
		done
	fi
}

# Usage: __host_show [ NAME ]
__host_show() {
	if [ "${#}" -eq 0 ]; then
		__host_list
		return
	fi

	__host_exec "${1}" ip -br address show
}

# Usage: __host_del NAME
__host_del() {
	_host_name="${HOST_PREFIX}${1:?error: host name is empty}"; __validate "${_host_name}"

	__ip netns delete "${_host_name}"
}

# Usage: __host_connect NAME NETWORK IP
__host_connect() {
	_host_name="${HOST_PREFIX}${1:?error: NAME name is empty}"; __validate "${_host_name}"
	_host_connect_net="${NETWORK_PREFIX}${2:?error: NETWORK is empty}"; __validate "${_host_connect_net}"
	_host_connect_ip="${3:?error: IP is empty}"
	_host_connect_host_dev="${2}"
	_host_connect_net_dev="${1}"

	# only run this check if we are actually executing
	if [ "${Dump}" -eq 0 ]; then
		ip -n "${_host_connect_net}" link show br0 > /dev/null || __error "unable to verify that br0 exists in ${2}"
	fi

	__ip -n "${_host_connect_net}" link add "${_host_connect_net_dev}" type veth peer name "${_host_connect_host_dev}" netns "${_host_name}"
	__ip -n "${_host_connect_net}" link set "${_host_connect_net_dev}" master br0

	__ip -n "${_host_connect_net}" addr add "${_host_connect_ip}" dev "${_host_connect_net_dev}"
	__ip -n "${_host_name}" addr add "${_host_connect_ip}" dev "${_host_connect_host_dev}"

	__ip -n "${_host_connect_net}" link set "${_host_connect_net_dev}" up
	__ip -n "${_host_name}" link set "${_host_connect_host_dev}" up
}

# Usage: __host_shell NAME
__host_shell() {
	_host_name="${HOST_PREFIX}${1:?error: NAME is empty}"; __validate "${_host_name}"

	if [ -z "${SHELL}" ]; then
		# shellcheck disable=SC2016
		__error '$SHELL is empty'
	fi

	# maintain SHLVL accordingly, even if not explicitly supported by this shell
	# shellcheck disable=SC2039
	_host_shell_lvl=$(( ${SHLVL:-1} + 1 ))

	# we are probably run as sudo, try to guess the real user
	_host_exec_uid="${SUDO_UID:-0}"

	__ip netns exec "${_host_name}" env NS_HOST="${1}" SHLVL="${_host_shell_lvl}" su -w NS_HOST,SHLVL "$(id -un "${_host_exec_uid}")" --login
}

__host() {
	_host_cmd="${1:-show}"
	__shift
	case "${_host_cmd}" in
		e | exec )         __host_exec "${@}" ;;
		a | add )          __host_add "${@}" ;;
		l | list )         __host_list "${@}" ;;
		s | show )         __host_show "${@}" ;;
		d | del | delete ) __host_del "${@}" ;;
		c | connect )      __host_connect "${@}" ;;
		sh | shell )       __host_shell "${@}" ;;
		help )             __help host ;;
		* )                __error "unknown command '${_host_cmd}', try 'ns host help'" ;;
	esac
}

# Usage: __net_exec NAME COMMAND ARGS...
__net_exec() {
	_net_name="${NETWORK_PREFIX}${1:?error: NAME is empty}"; __validate "${_net_name}"
	__shift

	if [ "${#}" -eq 0 ]; then __error "COMMAND is empty"; fi

	__ip netns exec "${_net_name}" "${@}"
}

# Usage: __net_add NAME
__net_add() {
	_net_name="${NETWORK_PREFIX}${1:?error: NAME is empty}"; __validate "${_net_name}"

	__ip netns add "${_net_name}"
	__ip -n "${_net_name}" link set lo up

	# peers on a network are connected using a bridge
	__ip -n "${_net_name}" link add br0 type bridge
	__ip -n "${_net_name}" link set br0 up
}

__net_list() {
	if [ "$(id -u)" -ne 0 ]; then
		ip netns show | grep "^${NETWORK_PREFIX}" | __strip_prefix | sort
	else
		ip netns show | grep "^${NETWORK_PREFIX}" | sort | while read -r _net_name; do
			echo "$(echo "${_net_name}" | __strip_prefix) ($(ip -o -n "${_net_name}" link show | grep -oP '[a-zA-Z0-9]+(?=@[a-zA-Z0-9]+)' | sort | xargs))"
		done
	fi
}

# Usage: __host_show [ NAME ]
__net_show() {
	if [ "${#}" -eq 0 ]; then
		__net_list
		return
	fi

	__net_exec "${1}" ip -br address show
}

# Usage: __net_del NAME
__net_del() {
	_net_name="${NETWORK_PREFIX}${1:?error: NAME is empty}"; __validate "${_net_name}"

	__ip netns delete "${_net_name}"
}

__net() {
	_net_cmd="${1:-show}"
	__shift
	case "${_net_cmd}" in
		e | exec )         __net_exec "${@}" ;;
		a | add )          __net_add "${@}" ;;
		l | list )         __net_list "${@}" ;;
		s | show )         __net_show "${@}" ;;
		d | del | delete ) __net_del "${@}" ;;
		help )             __help net ;;
		* )                __error "unknown command '${_net_cmd}', try 'ns net help'" ;;
	esac
}

__batch() {
	_batch_file="${1:?error: FILE is empty}"

	if [ ! -f "${_batch_file}" ]; then __error "'${_batch_file}' is not a file"; fi

	while read -r _batch_line; do
		if [ -z "${_batch_line}" ] || [ "#" = "$(echo "${_batch_line}" | cut -c -1)" ]; then
			continue
		fi

		_batch_opts=""
		if [ "${Dump}" != 0 ]; then _batch_opts="${_batch_opts} -d"; fi

		eval "ns ${_batch_opts} ${_batch_line}" || [ "${Force}" != 0 ]
	done < "${_batch_file}"
}

__help() {
	_help_cmd="${1}"
	case "${_help_cmd}" in
		"" )
			echo "Usage: ns [ FLAGS ] COMMAND [ ARGS ]"
			echo
			echo "ns - simulate different network topologies."
			echo
			echo "Commands:"
			echo "  net"
			echo "    add     NAME"
			echo "    show"
			echo "    delete  NAME"
			echo "    exec    NAME COMMAND [ ARGS ]"
			echo "  host"
			echo "    add     NAME"
			echo "    show"
			echo "    delete  NAME"
			echo "    connect NAME NETWORK IP"
			echo "    exec    NAME COMMAND [ ARGS ]"
			echo "  batch     FILE"
			echo "  help"
			echo "    net"
			echo "    host"
			echo "    help"
			echo
			echo "Commands and sub-commands may be abbreviated, e.g. 'h' instead of 'host' or"
			echo "'a' instead of 'add'. If two or more commands start with the same letter the"
			echo "more common command is selected, e.g. 's' is the same as 'show' and 'shell'"
			echo "can be abbreviated as 'sh'. Try to catch them all!"
			echo
			echo "Flags:"
			echo "  -v --verbose Enable debug logging using 'set -x'."
			echo "  -d --dump    Print ip commands to stdout instead of executing them."
			echo "  -f --force   Don't stop on the first error in batch mode."
			echo
			echo "Dependencies:"
			echo "  grep(1)"
			echo "  ip(8)"
			echo "  sed(1)"
			;;
		net )
			echo "Usage: ns net [ list | show ]"
			echo "       ns net { add | delete } NAME"
			echo "       ns net ip IP_COMMAND"
			echo
			echo "ns net [ list | show ]"
			echo "  Show all existing networks. If invoked as root the output will include the"
			echo "  connected hosts in parentheses after the network name."
			echo
			echo "ns net { add | delete | show } NAME"
			echo "  Add, delete or show the named network."
			echo
			echo "ns net exec NAME COMMAND [ ARGS ]"
			echo "  Execute COMMAND in the namespace of the network."
			;;
		host )
			echo "Usage: ns host [ list | show ]"
			echo "       ns host { add | delete | show } NAME"
			echo "       ns host connect NAME NETWORK DEVICE NETWORK-DEVICE IP"
			echo "       ns host shell NAME"
			echo "       ns host ip NAME IP_COMMAND"
			echo
			echo "ns host [ list | show ]"
			echo "  List all existing hosts. If invoked as root the output will include the"
			echo "  networks the host is connected to in parentheses after the host name."
			echo
			echo "ns host { add | delete | show } NAME"
			echo "  Add, delete or show the named host."
			echo
			echo "ns host connect NAME NETWORK IP"
			echo "  Add the host with NAME to NETWORK. Each side will get an device. IP will be"
			echo "  assigned to both interfaces."
			echo
			echo "ns host shell NAME"
			echo "  Spawn a shell on the host with NAME. The command will try to identify the"
			echo "  calling user and run a login shell for that user (defaults to root)."
			echo
			echo "ns host exec NAME COMMAND [ ARGS ]"
			echo "  Execute COMMAND in the namespace of the host."
			;;
		batch )
			echo "Usage: ns batch FILE"
			echo
			echo "Process commands from FILE. If -d is given it is passed on to each command. This"
			echo "allows for converting a batch file to a shell script of ip commands."
			;;
		help )
			echo "Usage: ns help { net | host | help | batch }"
			;;
		* ) __error "unknown command '${_help_cmd}', try 'ns help help'" ;;
	esac
}

__ns() {
	while :; do
		case "${1}" in
			-v | --verbose ) set -x ;;
			-d | --dump )    Dump=1 ;;
			-f | --force )   Force=1 ;;
			-* )             __error "unknown flag '${1}'" ;;
			* )              break ;;
		esac
		__shift
	done

	_cmd="${1:-help}"
	__shift
	case "${_cmd}" in
		h | host ) __host "${@}" ;;
		n | net )  __net  "${@}" ;;
		batch )    __batch "${@}" ;;
		help )     __help "${@}" ;;
		* )        __error "unknown command '${_cmd}', try 'ns help'" ;;
	esac
}

__ns "${@}"
