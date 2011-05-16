#
# WHAT: disk device plugin
# PURPOSE: initialize/mount disk devices
#

#
# Id: $Id: disk.inc.sh 36 2006-10-19 07:22:37Z bfg $
# Last changed on: $LastChangedDate: 2006-10-19 09:22:37 +0200 (Thu, 19 Oct 2006) $
# Last changed by: $LastChangedBy: bfg $
#

##############################################
#         PLUGIN SPECIFIC GLOBALS            #
##############################################

##############################################
#           "PUBLIC" FUNCTIONS               #
##############################################

plugin_disk_init_onload() {
	return 0
}

plugin_disk_initialized() {
	return 0
}

plugin_disk_init() {
	# wait disk to become available
	blockdev_wait "${1}"
}

plugin_disk_can_handle_rootdev() {
	local r=1
	if echo "${1}" | egrep '^\/dev/[hs]d[a-z][0-9]+$' >/dev/null 2>&1; then
		r=0
	fi
	return $r
}

plugin_disk_mount() {
	blockdev_mount "${1}" "${2}"
}

plugin_disk_deinit() {
	return 0
}

##############################################
#           "PRIVATE" FUNCTIONS              #
##############################################

# EOF