#
# WHAT: device-mapper device plugin
# PURPOSE: initialize/mount LVM2/DMRAID devices
#

#
# Id: $Id: devmapper.inc.sh 36 2006-10-19 07:22:37Z bfg $
# Last changed on: $LastChangedDate: 2006-10-19 09:22:37 +0200 (Thu, 19 Oct 2006) $
# Last changed by: $LastChangedBy: bfg $
#

##############################################
#         PLUGIN SPECIFIC GLOBALS            #
##############################################

_DEVMAPPER_INIT_DONE=0

##############################################
#           "PUBLIC" FUNCTIONS               #
##############################################

plugin_devmapper_init_onload() {
	return 0
}

plugin_devmapper_initialized() {
	if [ "${_DEVMAPPER_INIT_DONE}" = "1" ]; then
		return 0
	else
		return 0
	fi
}

plugin_devmapper_can_handle_rootdev() {
	local r=1
	if echo "${1}" | egrep -i '^\/dev\/mapper\/[a-z_-\.0-9]+' >/dev/null 2>&1; then
		r=0
	fi
	return $r
}

plugin_devmapper_init() {
	# run lvm subsystem init
	_plugin_devmapper_init

	# wait disk to become available
	blockdev_wait "${1}"
}

plugin_devmapper_mount() {
	blockdev_mount "${1}" "${2}"
}

plugin_devmapper_deinit() {
	return 0
}

##############################################
#           "PRIVATE" FUNCTIONS              #
##############################################

# really initializes LVM2 subsystem...
_plugin_devmapper_init() {
	if [ "${_DEVMAPPER_INIT_DONE}" = "1" ]; then
		return 0
	fi
	
	# discover software raid arrays...
	msg_info "Scanning for DMRaid arrays."
	dmraid -ay >/dev/null 2>&1

	# discover LVM volumes
	msg_info "Scanning for LVM2 volume groups."
	vgscan --ignorelockingfailure 2>/dev/null
	
	# activate LVM volumes
	if [ "$?" = "0" ]; then
		msg_info "Activating LVM2 volume groups."
		vgchange -ay --ignorelockingfailure
	else
		msg_warn "No LVM2 volume groups found."
	fi

	_DEVMAPPER_INIT_DONE=1
}

# EOF