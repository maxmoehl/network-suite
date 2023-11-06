#!/bin/sh -e

Dump=0

__error() {
	echo "error: ${*}" > /dev/stderr
	return 1
}

# shift can exit with a non-zero code if there are no more arguments, we
# don't want that.
alias __shift='test "${#}" -gt 0 && shift'

# Usage: __validate NAME
__validate() {
	# reserved names
	if [ "${1}" = "lo" ]; then __error "'lo' is a reserved name"; fi
	if [ "${1}" = "br0" ]; then __error "'br0' is a reserved name"; fi

	# must be a valid device name
	if ! expr "${1}" : "^[a-zA-Z0-9_-]\{1,15\}$" > /dev/null; then __error "'${1}' is not a valid name"; fi
}

# Execute ip commands or dump them to stdout.
__ip() {
	if [ "${Dump}" -eq 1 ]; then
		echo "ip ${*}"
	else
		ip "${@}"
	fi
}

# Usage: __host_add NAME
__host_add() {
	_host_name="${1:?error: NAME is empty}"; __validate "${_host_name}"

	__ip netns add "host-${_host_name}"
	__ip -n "host-${_host_name}" link set lo up
}

__host_show() {
	__ip netns show | grep '^host-' | sed -e 's/host-//'
}

# Usage: __host_del NAME
__host_del() {
	_host_name="${1:?error: host name is empty}"; __validate "${_host_name}"

	__ip netns delete "host-${_host_name}"
}

# Usage: __host_connect NAME NETWORK IP
__host_connect() {
	_host_name="${1:?error: NAME name is empty}"; __validate "${_host_name}"
	_host_connect_net="${2:?error: NETWORK is empty}"; __validate "${_host_connect_net}"
	_host_connect_ip="${3:?error: IP is empty}"
	_host_connect_host_dev="${_host_connect_net}"
	_host_connect_net_dev="${_host_name}"

	# only run this check if we are actually executing
	if [ "${Dump}" -eq 0 ]; then
		ip -n "network-${_host_connect_net}" link show br0 > /dev/null || __error "unable to verify that br0 exists in ${_host_connect_net}"
	fi

	__ip -n "network-${_host_connect_net}" link add "${_host_connect_net_dev}" type veth peer name "${_host_connect_host_dev}" netns "host-${_host_name}"
	__ip -n "network-${_host_connect_net}" link set "${_host_connect_net_dev}" master br0

	__ip -n "network-${_host_connect_net}" addr add "${_host_connect_ip}" dev "${_host_connect_net_dev}"
	__ip -n "host-${_host_name}" addr add "${_host_connect_ip}" dev "${_host_connect_host_dev}"

	__ip -n "network-${_host_connect_net}" link set "${_host_connect_net_dev}" up
	__ip -n "host-${_host_name}" link set "${_host_connect_host_dev}" up
}

# Usage: __host_shell NAME
__host_shell() {
	_host_name="${1:?error: NAME is empty}"; __validate "${_host_name}"

	if [ -z "${SHELL}" ]; then
		# shellcheck disable=SC2016
		__error '$SHELL is empty'
	fi

	# we are probably run as sudo, try to guess the real user
	_host_exec_uid="${SUDO_UID:-0}"

	__ip netns exec "host-${_host_name}" su "$(id -un "${_host_exec_uid}")" --login
}

# Usage: __host_ip NAME IP_COMMAND...
__host_ip() {
	_host_name="${1:?error: NAME is empty}"; __validate "${_host_name}"
	__shift

	if [ "${#}" -eq 0 ]; then __error "IP_COMMAND is empty"; fi

	__ip -n "host-${_host_name}" "${@}"
}

__host() {
	_host_cmd="${1:-show}"
	__shift
	case "${_host_cmd}" in
		add )          __host_add "${@}" ;;
		show | list )  __host_show "${@}" ;;
		delete | del ) __host_del "${@}" ;;
		connect )      __host_connect "${@}" ;;
		shell )        __host_shell "${@}" ;;
		ip )           __host_ip "${@}" ;;
		help )         __help host ;;
		* )            __error "unknown command '${_host_cmd}', try 'ns host help'" ;;
	esac
}

# Usage: __net_add NAME
__net_add() {
	_net_name="${1:?error: NAME is empty}"; __validate "${_net_name}"

	__ip netns add "network-${_net_name}"
	__ip -n "network-${_net_name}" link set lo up

	# peers on a network are connected using a bridge
	__ip -n "network-${_net_name}" link add br0 type bridge
	__ip -n "network-${_net_name}" link set br0 up
}

__net_show() {
	__ip netns show | grep '^network-' | sed -e 's/network-//'
}

# Usage: __net_del NAME
__net_del() {
	_net_name="${1:?error: NAME is empty}"; __validate "${_net_name}"

	__ip netns delete "network-${_net_name}"
}

# Usage: __net_ip NAME IP_COMMAND...
__net_ip() {
	_net_name="${1:?error: NAME is empty}"; __validate "${_net_name}"
	__shift

	if [ "${#}" -eq 0 ]; then __error "IP_COMMAND is empty"; fi

	__ip -n "network-${_net_name}" "${@}"
}

__net() {
	_net_cmd="${1:-show}"
	__shift
	case "${_net_cmd}" in
		add )          __net_add "${@}" ;;
		show | list )  __net_show "${@}" ;;
		delete | del ) __net_del "${@}" ;;
		ip )           __net_ip "${@}" ;;
		help )         __help net ;;
		* )            __error "unknown command '${_net_cmd}', try 'ns net help'" ;;
	esac
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
			echo "    ip      NAME IP_COMMAND"
			echo "  host"
			echo "    add     NAME"
			echo "    show"
			echo "    delete  NAME"
			echo "    connect NAME NETWORK IP"
			echo "    ip      NAME IP_COMMAND"
			echo "  help"
			echo "    net"
			echo "    host"
			echo "    help"
			echo
			echo "Flags:"
			echo "  -v --verbose Enable debug logging using 'set -x'."
			echo "  -d --dump    Print ip commands to stdout instead of executing them."
			echo
			echo "Dependencies:"
			echo "  grep(1)"
			echo "  ip(8)"
			echo "  sed(1)"
			;;
		help )
			echo "Usage: ns help { net | host | help }"
			;;
		net )
			echo "Usage: ns net [ show ]"
			echo "       ns net { add | del } NAME"
			echo "       ns net ip IP_COMMAND"
			echo
			echo "ns net [ show ]"
			echo "  Show all existing networks."
			echo
			echo "ns net { add | del } NAME"
			echo "  Create or delete the named network."
			echo
			echo "ns net ip NAME IP_COMMAND"
			echo "  Execute an ip command in the namespace of the network."
			;;
		host )
			echo "Usage: ns host [ show ]"
			echo "       ns host { add | del } NAME"
			echo "       ns host connect NAME NETWORK DEVICE NETWORK-DEVICE IP"
			echo "       ns host shell NAME"
			echo "       ns host ip NAME IP_COMMAND"
			echo
			echo "ns host [ show ]"
			echo "  Show all existing hosts."
			echo
			echo "ns host { add | del } NAME"
			echo "  Create or delete the named host."
			echo
			echo "ns host connect NAME NETWORK IP"
			echo "  Add the host with NAME to NETWORK. Each side will get an device. IP will be"
			echo "  assigned to both interfaces."
			echo
			echo "ns host shell NAME"
			echo "  Spawn a shell on the host with NAME. The command will try to identify the"
			echo "  calling user and run a login shell for that user (defaults to root)."
			echo
			echo "ns host ip NAME IP_COMMAND"
			echo "  Execute an ip command in the namespace of the host."
			;;
		* ) __error "unknown command '${_help_cmd}', try 'ns help help'" ;;
	esac
}

__ns() {
	while :; do
		case "${1}" in
			-v | --verbose ) set -x ;;
			-d | --dump )    Dump=1 ;;
			-* )             __error "unknown flag '${1}'" ;;
			* )              break ;;
		esac
		__shift
	done

	_cmd="${1:-help}"
	__shift
	case "${_cmd}" in
		host ) __host "${@}" ;;
		net )  __net  "${@}" ;;
		help ) __help "${@}" ;;
		* )    __error "unknown command '${_cmd}', try 'ns help'" ;;
	esac
}

__ns "${@}"
