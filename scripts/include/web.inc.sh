#
# WHAT: linuxrc OS in image file plugin
# PURPOSE: allows loading OS image file http or ftp address,
#          extracting it to RAM and booting from it.
#

#
# Id: $Id: web.inc.sh 46 2006-10-26 12:28:58Z bfg $
# Last changed on: $LastChangedDate: 2006-10-26 14:28:58 +0200 (Thu, 26 Oct 2006) $
# Last changed by: $LastChangedBy: bfg $
#

##############################################
#         PLUGIN SPECIFIC GLOBALS            #
##############################################

_WEB_INITIALIZED=0
_WEB_PROXY=""

##############################################
#           "PUBLIC" FUNCTIONS               #
##############################################

plugin_web_init_onload() {
	_WEB_PROXY="`cmdline_get_val proxy`"
	return 0
}

plugin_web_initialized() {
	return 0
}

plugin_web_init() {
	plugin_require "network"
	return 0
}

plugin_web_can_handle_rootdev() {
	local r=1
	if echo "${1}" | egrep -i '^(http|ftp):\/\/[a-z\.\-0-9]+(:[0-9]+)?\/' >/dev/null 2>&1; then
		r=0
	fi
	return $r
}

plugin_web_mount() {
	# mount ram filesystem
	tmpfs_mount "${2}"
	
	local wget_opt="-q"
	local tar_opt="xpf"
	
	
	local tar_enable="1"
	local sqfs_enable="0"
	local loop_enable="0"

	# tar, gzip, bzip archive?
	if echo "${1}" | egrep -i '\.tar$' >/dev/null 2>&1; then
		tar_opt="${tar_opt}"
	# bzipped tar?
	elif echo "${1}" | egrep -i '\.(tar\.bz2|tbz)$' >/dev/null 2>&1; then
		tar_opt="j${tar_opt}"
	# gzipped tar?
	elif echo "${1}" | egrep -i '\.(tar\.gz|tgz)$' >/dev/null 2>&1; then
		tar_opt="z${tar_opt}"
	# squashfs?
	elif echo "${1}" | egrep -i '\.(sq((uash)?(fs)?)?)$' >/dev/null 2>&1; then
		tar_enable=0
		sqfs_enable="1"
	# loopback image?
	elif echo "${1}" | egrep -i '\.img$' >/dev/null 2>&1; then
		tar_enable=0
		loop_enable="1"
	else
		die "I don't know how to unpack archive '${1}'"
	fi

	# hmmm, should we use web proxy?
	if [ ! -z "${_WEB_PROXY}" ]; then
		http_proxy="${_WEB_PROXY}"
		ftp_proxy="${_WEB_PROXY}"
		export http_proxy ftp_proxy
		wget_opt="${wget_opt} -Y on"
	fi

	# TAR ARCHIVE
	if [ "${tar_enable}" = "1" ]; then
		# download image, extract it on-the-fly to tmpfs
		# mount directory
		msg_info "Downloading archive '${TERM_RED}${1}${TERM_RESET}' and extracting it to '${TERM_YELLOW}${2}${TERM_RESET}."
		( wget ${wget_opt} -O - "${1}" | tar ${tar_opt} - -C "${2}" ) || die "Unable to download/extract image."
		msg_info "Image was successfuly downloaded and extracted."

		# remount ram filesystem read-only
		mount -o remount,ro "${2}" || die "Unable to remount filesystem '${TERM_LRED}${2}${TERM_RESET}' read-only."

	# SQUASHFS or LOOP device image
	else
		# create temporary mount point
		local mntdir=""
		mntdir=`mktemp -d /mnt/tmpmnt.XXXXXX`
		test $? -ne 0 && die "Unable to create tempoary directory for downloading operating system image."

		# compute local name
		local real_name="${mntdir}/`basename ${1}`"

		# mount ram filesystem
		tmpfs_mount "${mntdir}"

		# download image to mounted tmpfs...
		msg_info "Downloading archive '${TERM_RED}${1}${TERM_RESET}' to '${TERM_YELLOW}${real_name}${TERM_RESET}."
		wget ${wget_opt} -O "${real_name}" "${1}" || die "Unable to download download image."
		msg_info "Image was successfuly downloaded."

		# ok :) now try to mount image as new root :)
		
		# SQUASHFS
		if [ "${sqfs_enable}" = "1" ]; then
			# check for squashfs filesystem kernel support
			if ! grep squashfs /proc/filesystems >/dev/null 2>&1; then
				die "Unable to mount squashfs image: no kernel support for squashfs!"
			fi

			# mount squash fs image
			msg_info "Mounting ${TERM_LRED}squashfs${TERM_RESET} squashfs read-only image to '${TERM_YELLOW}${2}${TERM_RESET}'."
			mount -t squashfs -o ro,noatime "${realname}" "${2}" || die "Unable to mount squashfs image."

			# squashfs is always read-only, no need to remount ;)

		# LOOP DEVICE IMAGE
		elif [ "${loop_enable}" = "1" ]; then
			# check for loop device kernel support
			if ! grep ' loop' /proc/devices >/dev/null 2>&1; then
				die "Unable to mount loopback image: no kernel support for loopback devices!"
			fi

			# mount image read-only, and we're done ;)
			mount -o loop,ro "${real_file}" "${2}" || die "Unable to mount loopback device."

		else
			die "Undefined situation... this should never happen."
		fi
	fi

	# this is it..
	return 0
}

plugin_web_deinit() {
	return 0
}

##############################################
#           "PRIVATE" FUNCTIONS              #
##############################################

# EOF