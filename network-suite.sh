#!/bin/sh -e

__error() {
	echo "error: ${*}" > /dev/stderr
	return 1
}

# shift can exit with a non-zero code if there are no more arguments, we
# don't want that.
alias __shift='test "${#}" -gt 0 && shift'

# Usage: __host_add NAME
__host_add() {
	_host_name="host-${1:?error: host name is empty}"
	ip netns add "${_host_name}"
	ip -n "${_host_name}" link set lo up
}

__host_show() {
	ip netns show | grep '^host-' | sed -e 's/host-//'
}

# Usage: __host_del NAME
__host_del() {
	_host_name="host-${1:?error: host name is empty}"
	ip netns delete "${_host_name}"
}

# Usage: __host_connect NAME NETWORK DEVICE NETWORK-DEVICE IP
__host_connect() {
	_host_name="host-${1:?error: host name is empty}"
	_host_connect_net="network-${2:?error: network is empty}"
	_host_connect_dev="${3:?error: device name is empty}"
	_host_connect_net_dev="${4:?error: network device name is empty}"
	_host_connect_ip="${5:?error: ip is empty}"

	ip -n "${_host_connect_net}" link show br0 > /dev/null || __error "unable to verify that br0 exists in ${_host_connect_net}"

	ip -n "${_host_connect_net}" link add "${_host_connect_net_dev}" type veth peer name "${_host_connect_dev}" netns "${_host_name}"
	ip -n "${_host_connect_net}" link set "${_host_connect_net_dev}" master br0

	ip -n "${_host_connect_net}" addr add "${_host_connect_ip}" dev "${_host_connect_net_dev}"
	ip -n "${_host_name}" addr add "${_host_connect_ip}" dev "${_host_connect_dev}"

	ip -n "${_host_connect_net}" link set "${_host_connect_net_dev}" up
	ip -n "${_host_name}" link set "${_host_connect_dev}" up
}

__host() {
	_host_cmd="${1:-show}"
	__shift
	case "${_host_cmd}" in
		add )          __host_add "${@}" ;;
		show | list )  __host_show "${@}" ;;
		delete | del ) __host_del "${@}" ;;
		connect )      __host_connect "${@}" ;;
		help )         __help host ;;
		* )            __error "unknown command '${_host_cmd}', try 'ns host help'" ;;
	esac
}

# Usage: __net_add NAME
__net_add() {
	_net_name="network-${1:?error: network name is empty}"
	ip netns add "${_net_name}"
	ip -n "${_net_name}" link set lo up

	# peers on a network are connected using a bridge
	ip -n "${_net_name}" link add br0 type bridge
	ip -n "${_net_name}" link set br0 up
}

__net_show() {
	ip netns show | grep '^network-' | sed -e 's/network-//'
}

# Usage: __net_del NAME
__net_del() {
	_net_name="network-${1:?error: network name is empty}"
	ip netns delete "${_net_name}"
}

__net() {
	_net_cmd="${1:-show}"
	__shift
	case "${_net_cmd}" in
		add )          __net_add "${@}" ;;
		show | list )  __net_show "${@}" ;;
		delete | del ) __net_del "${@}" ;;
		help )         __help net ;;
		* )            __error "unknown command '${_net_cmd}', try 'ns net help'" ;;
	esac
}

__help() {
	_help_cmd="${1}"
	case "${_help_cmd}" in
		"" )
			echo "Usage: ns COMMAND [ ARGS ]"
			echo
			echo "ns - simulate different network topologies."
			echo
			echo "Commands:"
			echo "  net"
			echo "    add     NAME"
			echo "    show"
			echo "    delete  NAME"
			echo "  host"
			echo "    add     NAME"
			echo "    show"
			echo "    delete  NAME"
			echo "    connect NAME NETWORK DEVICE NETWORK-DEVICE IP"
			echo "  help"
			echo "    net"
			echo "    host"
			echo "    help"
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
			echo
			echo "ns net [ show ]"
			echo "  Show all existing networks."
			echo
			echo "ns net { add | del } NAME"
			echo "  Create or delete the named network."
			;;
		host )
			echo "Usage: ns host [ show ]"
			echo "       ns host { add | del } NAME"
			echo "       ns host connect NAME NETWORK DEVICE NETWORK-DEVICE IP"
			echo
			echo "ns host [ show ]"
			echo "  Show all existing hosts."
			echo
			echo "ns host { add | del } NAME"
			echo "  Create or delete the named host."
			echo
			echo "ns host connect NAME NETWORK DEVICE NETWORK-DEVICE IP"
			echo "  Add the host with NAME to NETWORK. Each side will get an device."
			echo "  DEVICE is the name of the interface at the host and"
			echo "  NETWORK-DEVICE will used in the network. IP will be assigned to"
			echo "  both interfaces."
			;;
		* ) __error "unknown command '${_help_cmd}', try 'ns help help'" ;;
	esac
}

__ns() {
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
