#
# WHAT: linuxrc OS in tar(gz|bz2) archive / squashfs / loopback image plugin
# PURPOSE: allows loading image file from some device,
#          extracting it to RAM and booting from it.
#

#
# Id: $Id: archive.inc.sh 47 2006-10-26 12:30:06Z bfg $
# Last changed on: $LastChangedDate: 2006-10-26 14:30:06 +0200 (Thu, 26 Oct 2006) $
# Last changed by: $LastChangedBy: bfg $
#

##############################################
#         PLUGIN SPECIFIC GLOBALS            #
##############################################

_ARCHIVE_BDEVSETTLE_TIMEOUT=7
_ARCHIVE_OPPMOUNT_BLOCKDEVS=""

##############################################
#           "PUBLIC" FUNCTIONS               #
##############################################

plugin_archive_init_onload() {
	return 0
}

plugin_archive_initialized() {
	return 0
}

plugin_archive_init() {
	return 0
}

plugin_archive_can_handle_rootdev() {
	local r=1
	if echo "${1}" | egrep -i '^(\/dev/[hs]d[a-z][0-9])?:\/.+(\.tar|tgz|tbz|tar\.gz|tar\.bz2|\.img|\.sq((uash)?(fs)?)?)$' >/dev/null 2>&1; then
		r=0
	# some weird cdrom/dvdrom/writer devices,
	# software raid arrays
	elif echo "${1}" | egrep -i '^\/dev/(md|sr)[0-9]+:\/.+(\.tar|tgz|tbz|tar\.gz|tar\.bz2|\.img|\.sq((uash)?(fs)?)?)$' >/dev/null 2>&1; then
		r=0
	fi
	return $r
}

plugin_archive_mount() {
	# create temporary mount point
	local mntdir=""
	mntdir=`mktemp -d /mnt/tmpmnt.XXXXXX`
	test $? -ne 0 && die "Unable to create tempoary directory for mounting operating system image."

	# extract device name from
	# specified file
	local dev="`_plugin_archive_get_device ${1}`"
	local imgfile="`_plugin_archive_get_imagefile ${1}`"
	test -z "${imgfile}" && die "Invalid root device syntax '${1}': unable to extract operating system image file name. ${TERM_LRED}Valid syntax${TERM_RESET}: ${TERM_BOLD}/dev/<name>:</path/to/image>${TERM_RESET}"
	
	# compute real filename
	local real_file="${mntdir}/${imgfile}"
	real_file="`echo ${real_file} | sed -e 's/\/\//\//g' | sed -e 's/\.\.//g'`"

	# if we have empty device, we should
	# oppurtunistically mount every block
	# device and search for OS image
	if [ -z "${dev}" ]; then
		_plugin_archive_opportunistic_mount "${mntdir}" "${imgfile}" || die "Unable to find device holding operating system image '${TERM_YELLOW}${imgfile}${TERM_RESET}'."
	else
		# wait for device...
		blockdev_wait "${dev}"

		# try to mount device to mount directory
		blockdev_mount "${dev}" "${mntdir}"

		# check for os image existence
		if [ ! -f "${real_file}" -o ! -r "${real_file}" ]; then
			# umount device
			umount -f "${mntdir}" >/dev/null 2>&1
			die "Invalid real_root device specification '${1}': Image file '${imgfile}' does not exist on '${dev}'."
		fi
	fi

	# ok, are we dealing with squashfs root image?
	if echo "${real_file}" | egrep '\.sq(uashfs)?$' >/dev/null 2>&1; then
		# check for squashfs filesystem kernel support
		if ! grep squashfs /proc/filesystems >/dev/null 2>&1; then
			die "Unable to mount squashfs image: no kernel support for squashfs!"
		fi

		# mount squash fs image
		msg_info "Mounting ${TERM_LRED}squashfs${TERM_RESET} squashfs read-only image to '${TERM_YELLOW}${2}${TERM_RESET}'."
		mount -t squashfs -o ro "${real_file}" "${2}" || die "Unable to mount squashfs image."

		# squashfs is always read-only, no need to remount ;)

	# are we dealing with loopback image?
	elif echo "${real_file}" | egrep '\.img$' >/dev/null 2>&1; then
		# check for loop device kernel support
		if ! grep ' loop' /proc/devices >/dev/null 2>&1; then
			die "Unable to mount loopback image: no kernel support for loopback devices!"
		fi

		# mount image read-only, and we're done ;)
		mount -o loop,ro "${real_file}" "${2}" || die "Unable to mount loopback device."

	# i guess, that we just have a tar archive... extract it into tmpfs :)
	else
		# mount ram filesystem
		tmpfs_mount "${2}"

		# unpack image
		unpack_archive "${real_file}" "${2}"

		# umount source filesystem...
		msg_info "Umounting '${TERM_LRED}${dev}${TERM_RESET}' from '${TERM_YELLOW}${mntdir}${TERM_RESET}'."
		umount -f "${mntdir}" >/dev/null 2>&1

		# remount ram filesystem read-only
		mount -o remount,ro "${2}" || die "Unable to remount filesystem '${TERM_LRED}${2}${TERM_RESET}' read-only."
	fi

	# this is it..
	return 0
}

plugin_archive_deinit() {
	return 0
}

##############################################
#           "PRIVATE" FUNCTIONS              #
##############################################

_plugin_archive_oppmount_get_devs() {
	local list=""
	local mdev=""

	msg_info "Waiting block devices to settle down (${_ARCHIVE_BDEVSETTLE_TIMEOUT} sec)."
	sleep ${_ARCHIVE_BDEVSETTLE_TIMEOUT}

	for mdev in /sys/block/md* /sys/block/hd* /sys/block/sd* /sys/block/sr*; do
		# check validity
		if [ ! -d "${mdev}" ]; then
			continue
		fi

		# check for subdevices
		local mdev_basename=`basename "${mdev}"`
		local count=0
		local m=""
		for m in ${mdev}/${mdev_basename}[0-9]*; do
			if [ ! -d "${m}" ]; then
				continue
			fi
			count=$((count + 1))
			m=`basename "${m}"`
			list="${list} ${m}"
		done

		if [ $count -eq 0 ]; then
			m=`basename "${mdev}"`
			list="${list} ${m}"
		fi
	done

	# save list into global...
	_ARCHIVE_OPPMOUNT_BLOCKDEVS="${list}"
}

_plugin_archive_opportunistic_mount() {
	local mntpoint="${1}"
	local file="${2}"

	echo ""
	msg_warn "No real root device specified, starting ${TERM_LGREEN}opportunistic mount${TERM_RESET}."
	echo ""

	local dev=""
	local real_file="${mntpoint}/${file}"

	# just for the sake of security...
	real_file=`echo "${real_file}" | sed -e 's/\/\//\//g' | sed -e 's/\.\.//g'`
	
	# discover all suitable block devices
	_plugin_archive_oppmount_get_devs

	for dev in ${_ARCHIVE_OPPMOUNT_BLOCKDEVS}; do
		dev="/dev/${dev}"
		msg_info "Opportunistic mount: checking device '${TERM_LRED}${dev}${TERM_RESET}'."

		# waiting for block device here is senseless,
		# becouse _get_devs() function detects only already
		# settled/established devices..

		# device is up, let's mount it
		! mount -o ro "${dev}" "${mntpoint}" >/dev/null 2>&1 && continue

		# mount succeeded. great, check for file
		if [ -r "${real_file}" -a -f "${real_file}" ]; then
			# we found the bastard...
			# return success, but leave filesystem mounted...
			msg_info "${TERM_LGREEN}Operating system package found on device ${TERM_RESET}'${TERM_LRED}${dev}${TERM_RESET}'."
			echo ""
			return 0
		else
			# umount the bastard
			umount -f "${mntpoint}" >/dev/null 2>&1
		fi
	done

	return 1
}

_plugin_archive_get_device() {
	echo "${1}" | cut -d: -f1
}

_plugin_archive_get_imagefile() {
	echo "${1}" | cut -d: -f2
}

# EOF