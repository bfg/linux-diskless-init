#
# WHAT: Networking linuxrc plugin
# PURPOSE: initialize network interfaces (assigns addresses)
#

#
# Id: $Id: network.inc.sh 36 2006-10-19 07:22:37Z bfg $
# Last changed on: $LastChangedDate: 2006-10-19 09:22:37 +0200 (Thu, 19 Oct 2006) $
# Last changed by: $LastChangedBy: bfg $
#

##############################################
#         PLUGIN SPECIFIC GLOBALS            #
##############################################

_NETWORK_INITIALIZED=0
_NETWORK_HAVE_IPV6=0

##############################################
#           "PUBLIC" FUNCTIONS               #
##############################################

plugin_network_init_onload() {
	return 0
}

plugin_network_initialized() {
	if [ "${_NETWORK_INITIALIZED}" = "1" ]; then
		return 0
	else
		return 1
	fi
}

# this is just meta plugin, by it
# cannot handle any root device by itself
plugin_network_can_handle_rootdev() {
	return 1
}

# initialize network cards
plugin_network_init() {
	if [ "${_NETWORK_INITIALIZED}" = "1" ]; then
		return 0
	fi

	# check if we're ipv6 enabled
	test -d "/sys/module/ipv6" && _NETWORK_HAVE_IPV6=1
	
	# bring up loop dev
	_plugin_network_init_loop

	# now bring up other network devices
	local dev=""
	local count=0
	for dev in `_plugin_network_dev_list`; do
		if _plugin_network_init_dev ${dev}; then
			count=$((count + 1))
		fi
	done

	if [ ${count} -gt 0 ]; then
		_NETWORK_INITIALIZED=1
	fi
	
	return 0
}

plugin_network_deinit() {
	if [ "${_NETWORK_INITIALIZED}" = "0" ]; then
		return 0
	fi
	
	# shutdown other network devices
	local dev=""
	for dev in `_plugin_network_dev_list`; do
		_plugin_network_deinit_dev ${dev}
	done

	# shutdown loop device
	_plugin_network_deinit_loop

	_NETWORK_INITIALIZED=0
	return 0
}

##############################################
#           "PRIVATE" FUNCTIONS              #
##############################################

_plugin_network_init_loop() {
	msg_info "Starting loopback network interface."
	ip addr add 127.0.0.1/8 dev lo || die "Unable to assign IPv4 loopback device address. Does kernel support tcp/ip networking?"
	ip link set dev lo up || die "Unable to bring loopback device up. This is weird..."
	
	# add ipv6 loopback address, if we're ipv6 enabled
	if [ "${_NETWORK_HAVE_IPV6}" = "1" ]; then
		ip addr add ::1/128 dev lo || die "Unable to assign IPv6 loopback device address."
	fi
	
	return 0
}

_plugin_network_deinit_loop() {
	msg_info "Shutting down loopback network interface."
	ip addr flush dev lo >/dev/null 2>&1
	ip link set dev lo down >/dev/null 2>&1
}

_plugin_network_dev_list() {
	ifconfig -a | egrep '^[a-z0-9]+ ' | grep 'Ethernet' | awk '{print $1}'
}

_plugin_network_init_dev() {
	# start dhcp client for specified device
	msg_info "Starting network interface ${1}."

	# bring up the interface
	ip link set dev "${1}" up

	# start dhcp client in background
	udhcpc -b -p "/var/run/udhcpc.${1}.pid" -i "${1}" 2>1 | logger

	# TODO: IPv6 support
	# i'm not quite shure if udchpc supports ipv6...
}

_plugin_network_deinit_dev() {
	msg_info "Stopping network interface ${1}."

	# shutdown dhcp client
	local pid="`cat /var/run/udhcpc.${1}.pid`"
	if [ ! -z "${pid}" ]; then
		kill -SIGUSR2 ${pid}
		kill ${pid}
	fi

	# well... shutdown device ;)
	ip addr flush dev ${1} >/dev/null 2>&1
	ip link set dev ${1} down >/dev/null 2>&1
}

# EOF