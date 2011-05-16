#!/bin/ash
#
# WHAT: Linux initrd /sbin/init script
# AUTHOR: Brane F. Gracnar <bfg@interseek.si>
# 

#
# Id: $Id: linuxrc.sh 8 2006-10-18 17:56:52Z bfg $
# Last changed on: $LastChangedDate: 2006-10-18 17:56:52Z $
# Last changed by: $LastChangedBy: bfg $
#

##############################################
#                 GLOBALS                    #
##############################################

# Abstract real root device description.
# This can be:
#	- block device (/dev/hda1, /dev/sda1, ...)
#	- lvm2 volume
# 	- dmraid array
#	- path to archive stored on some block device, that is going to be extracted to tmpfs
#	- http/ftp url address of an archive, that is going to be extracted to tmpfs
#
# Type: string
# Default: ""
# Command line parameter: real_root
REAL_ROOTDEV=""

# Real init program, that should be
# ran after changing to real root filesystem
#
# Type: string
# Default: "/sbin/init"
# Command line parameter: real_init
REAL_INIT="/sbin/init"

# Initialize initrd environment, but don't
# start real operating system. Run interactive
# failback console instead.
#
# Type: boolean
# Default: 0
# Command line parameter: failback
FAILBACK_MODE="0"

# Default size of mounted tmpfs filesystem
# if it is going to be used as root
# filesystem.
#
# Type: string
# Default: "250M" (250 MBytes)
# Command line parameter: tmpfs_size
TMPFS_SIZE="250M"

# How many seconds should this script
# wait before rebooting system if
# fatal error accours?
#
# NOTICE: DIE_REBOOT must be enabled.
#
# Type: integer
# Default: 10
# Command line parameter: die_timeout
DIE_TIMEOUT="10"

# Type of mounted ram-based filesystem.
#
# Possible values: tmpfs, ramfs
#
# Type: string
# Default: "tmpfs"
# Command line parameter: tmpfs_type
TMPFS_TYPE="tmpfs"

# Directory where real root filesystem should
# be moutend. Don't change unless you really
# know what you're doing.
#
# Type: string
# Default: "/realroot"
REAL_ROOTDIR="/realroot"

# Reboot system if fatal error
# accours?
#
# Type: boolean
# Default: 1
DIE_REBOOT="1"

# Timeout in seconds while waiting
# for specified block device to become
# available for usage.
#
# Type: integer
# Default: 30
BLOCKDEV_TIMEOUT="30"

# Debug
DEBUG="0"

##############################################
#                FUNCTIONS                   #
##############################################

VERSION="0.14"

PATH=/bin:/sbin:/usr/bin:/usr/sbin
export PATH

# kernel printk backup variable
KERNEL_PRINTK=""

# init boot type. possible values: initrd, initramfs
INITRD_TYPE="initrd"

# real root filesystem pivot_root directory
INITRD_DIR="initrd"

# list of loaded plugins
LOADED_PLUGINS=""

# pseudofs initialized flag
PSEUDO_FS_INITIALIZED=0

# SHELL color codes
TERM_WHITE="\033[1;37m"
TERM_YELLOW="\033[1;33m"
TERM_LPURPLE="\033[1;35m"
TERM_LRED="\033[1;31m"
TERM_LCYAN="\033[1;36m"
TERM_LGREEN="\033[1;32m"
TERM_LBLUE="\033[1;34m"
TERM_DGRAY="\033[1;30m"
TERM_GRAY="\033[0;37m"
TERM_BROWN="\033[0;33m"
TERM_PURPLE="\033[0;35m"
TERM_RED="\033[0;31m"
TERM_CYAN="\033[0;36m"
TERM_GREEN="\033[0;32m"
TERM_BLUE="\033[0;34m"
TERM_BLACK="\033[0;30m"
TERM_BOLD="\033[40m\033[1;37m"
TERM_RESET="\033[0m"

HAS_RUN_INIT=0

##############################################
#            MESSAGE FUNCTIONS               #
##############################################

msg_info() {
	logger "info: $@"
	echo -e "${TERM_BOLD}INFO   :${TERM_RESET} $@ ${TERM_RESET}"
}

msg_warn() {
	logger "warn: $@"
	echo -e "${TERM_YELLOW}WARNING:${TERM_RESET} $@ ${TERM_RESET}"
}

msg_err() {
	logger "error: $@"
	echo -e "${TERM_LRED}ERROR  :${TERM_RESET} $@ ${TERM_RESET}"
}

msg_debug() {
	test "${DEBUG}" = "1" || return 0
	logger "debug: $@"
	echo -e "${TERM_DGRAY}DEBUG  :${TERM_RESET} $@ ${TERM_RESET}"
}

##############################################
#            FATAL ERROR HANDLER             #
##############################################

die() {
	local x=""
	msg_err "$@"

	# run console if necessary
	if [ "${FAILBACK_MODE}" = "1" -o "${DIE_REBOOT}" = "0" ]; then
		failback_shell
	else
		msg_warn ""
		msg_warn "Fatal error accoured. System will reboot in ${DIE_TIMEOUT} seconds."
		msg_warn "${TERM_LGREEN}Press any key AND <ENTER>${TERM_RESET} to stop reboot sequence and enter failback shell."
		msg_warn ""
		read -t ${DIE_TIMEOUT} x
		test -z "${x}" && reboot
		failback_shell
	fi
}

##############################################
#     KERNEL COMMAND LINE FUNCTIONS          #
##############################################

# kernel command line function
cmdline_get_val() {
	cat /proc/cmdline | tr ' ' '\n' | grep "^${1}=" | cut -d= -f2 | tail -n 1
}

cmdline_param_exists() {
	grep -- "${1}" /proc/cmdline >/dev/null 2>&1
}

cmdline_get_val_bool() {
	local val=`cat /proc/cmdline | tr ' ' '\n' | egrep "^${1}\$" | tail -n 1`

	if [ -z "${val}" ]; then
		val="0"
	else
		val="1"
	fi

	echo $val | tr -d '"' | tr -d "'"
}

##############################################
#       ARCHIVE UNPACKING FUNCTIONS          #
##############################################

my_exec() {
	msg_debug "exec: $@"
	exec $@
}

cmd() {
	msg_debug "cmd: $@"
	eval $@
}

unpack_archive() {
	# plain tar?
	if echo "${1}" | egrep -i '\.tar$' >/dev/null 2>&1; then
		unpack_archive_tar "${1}" "${2}"
	# bzipped tar?
	elif echo "${1}" | egrep -i '\.(tar\.bz2|tbz)$' >/dev/null 2>&1; then
		unpack_archive_tbz "${1}" "${2}"
	# gzipped tar?
	elif echo "${1}" | egrep -i '\.(tar\.gz|tgz)$' >/dev/null 2>&1; then
		unpack_archive_tgz "${1}" "${2}"
	else
		# hm, tbz is default...
		time unpack_archive_tbz "${1}" "${2}"
	fi
	local rv=$?
	if [ $rv -ne 0 ]; then
		msg_warn "Command tar exited with non-zero status $rv."
	fi
}

unpack_archive_tar() {
	msg_info "Unpacking tar archive '${1}' to '${2}'."
	tar xpf "${1}" -C "${2}" 2>/dev/null
}

unpack_archive_tbz() {
	local t=""
	msg_info "Unpacking b2zipped tar archive '${1}' to '${2}'."
	t=`time tar jxpf "${1}" -C "${2}" 2>&1 | grep real | tail -n 1 | awk '{print $3}'`
	msg_info "Archive extracted in ${t}"
}

unpack_archive_tgz() {
	msg_info "Unpacking gzipped tar archive '${1}' to '${2}'."
	tar zxpf "${1}" -C "${2}" >/dev/null 2>&1
}

init_vars() {
	local x=""
	
	# debug?
	if cmdline_param_exists "debug" -o cmdline_param_exists "--debug"; then
		DEBUG="1"
	fi

	# determine runtype
	if [ "$0" = "/init" ]; then
		INITRD_TYPE="initramfs"
	else
		INITRD_TYPE="initrd"
	fi
	msg_info "Type: $INITRD_TYPE; my pid is: $$"

	# real root device
	x="`cmdline_get_val real_root`"
	test ! -z "${x}" && REAL_ROOTDEV="${x}"

	# check for real init
	x="`cmdline_get_val real_init`"
	test ! -z "${x}" && REAL_INIT="${x}"
	
	# user wants interactive console?
	x="`cmdline_get_val_bool failback`"
	FAILBACK_MODE="${x}"
	
	# tmpfs type?
	x="`cmdline_get_val tmpfs_type`"
	if [ "${x}" = "ramfs" ]; then
		TMPFS_TYPE="${x}"
	fi
	
	# tmpfs size?
	x="`cmdline_get_val tmpfs_size`"
	test ! -z "${x}" && TMPFS_SIZE="${x}"
	
	# die timeout
	x="`cmdline_get_val die_timeout`"
	test ! -z "${x}" && DIE_TIMEOUT="${x}"
	
	test -x "/bin/run-init" && HAS_RUN_INIT=1

	return 0
}

script_load_plugins() {
	# load plugins
	local f=""
	local name=""
	echo -ne "${TERM_BOLD}INFO   :${TERM_RESET} Loading plugins:${TERM_BOLD}"
	for f in /boot/include/*.inc.sh; do
		name="`basename ${f}`"
		name="`echo ${name} | cut -d. -f1`"
		echo -n " ${name}"
		source "${f}"
		# > /dev/null 2>&1

		# run plugin_<NAME>_init_onload function
		plugin_${name}_init_onload

		LOADED_PLUGINS="${LOADED_PLUGINS} ${name}"
	done
	LOADED_PLUGINS="${LOADED_PLUGINS} "

	echo -e "${TERM_RESET} done."
}

init() {
	# mount /proc & friends
	pseudo_fs_mount

	# initialize variables
	init_vars

	# / must be mounted RW	
	msg_info "Remounting initrd root filesystem RW"
	mount -o remount,rw /

	# populate device nodes
	udev_start
	
	# start syslog
	syslog_start

	# load kernel modules
	kernel_modules_load

	# load plugins
	script_load_plugins
}

deinit() {
	# deinitialize plugins
	local x=""
	for x in ${LOADED_PLUGINS}; do
		plugin_${x}_deinit
	done
	
	# stop mini udev
	udev_stop
	
	# stop syslog
	syslog_stop
}

deinit_full() {
	# standard deinit
	deinit

	# unmount pseudo filesystems
	pseudo_fs_umount	
}

rootdev_type() {
	# query all loaded plugins if they
	# are able mount this rootdevice type
	local x=""
	for x in ${LOADED_PLUGINS}; do
		if plugin_${x}_can_handle_rootdev "${REAL_ROOTDEV}"; then
			break
		fi
	done
	
	# if none of loaded plugins cannot handle this
	# rootdev type, we have a problem ;)
	#
	# the "unknown" plugin should "handle" this situation ;)
	#
	if [ -z "${x}" ]; then
		x="unknown"
	fi	
	echo "${x}"
}

pseudo_fs_mount() {
	if [ "${PSEUDO_FS_INITIALIZED}" = "1" ]; then
		return 0
	fi

	msg_info "Mounting pseudo-filesystems."
	/bin/mount -t proc none /proc
	/bin/mount -t sysfs none /sys
	/bin/mount -t devpts none /dev/pts

	# silence kernel
	KERNEL_PRINTK="`cat /proc/sys/kernel/printk`"
	echo 0 > "/proc/sys/kernel/printk"

	PSEUDO_FS_INITIALIZED=1
}

pseudo_fs_umount() {
	if [ "${PSEUDO_FS_INITIALIZED}" = "0" ]; then
		return 0
	fi

	# restore kernel printk
	echo "${KERNEL_PRINTK}" > "/proc/sys/kernel/printk" 2>/dev/null

	msg_info "Unmounting pseudo filesystems."
	/bin/umount -f /dev/pts
	/bin/umount -f /sys
	/bin/umount -f /proc
	
	PSEUDO_FS_INITIALIZED=0
}

# udev functions
udev_start() {
	msg_info "Populating device nodes."
	mdev -s || die "Unable to populate device nodes."
	msg_info "Setting up mdev as hotplug device manager."
	echo "/sbin/mdev" > "/proc/sys/kernel/hotplug"
}

udev_stop() {
	msg_info "Removing mdev as hotplug device manager."
	echo "" > "/proc/sys/kernel/hotplug"
}

syslog_start() {
	# kill any previous started syslog
	killall syslogd >/dev/null 2>&1

	msg_info "Starting syslogd."
	syslogd -C 128 >/dev/null 2>&1
}

syslog_stop() {
	msg_info "Stopping syslogd."
	killall -9 syslogd >/dev/null 2>&1
}

kernel_modules_load() {
	test -f /modules.load.conf || return 0
	
	echo -ne "${TERM_BOLD}INFO   :${TERM_RESET} Loading kernel modules:${TERM_BOLD}"
	local module=""
	for module in `cat /modules.load.conf | grep -v '^#'`; do
		test -z "${module}" && continue
		echo -n " ${module}"
		modprobe ${module} > /dev/null 2>&1
	done
	echo -e "${TERM_RESET} done."

	return 0
}

init_rootfs() {
	if [ -z "${REAL_ROOTDEV}" ]; then
		die "Kernel command line option 'real_root' was not set."
	fi
	
	local type="`rootdev_type`"
	test -z "${type}" && die "Empty rootdev type. This should never happen. Seems like plugin error."

	# run rootdev type plugin function
	plugin_${type}_init "${REAL_ROOTDEV}" || die "Unable to initialize root device '${REAL_ROOTDEV}'."

	# mount real root filesystem...
	plugin_${type}_mount "${REAL_ROOTDEV}" "${REAL_ROOTDIR}" || die "Unable to mount root device '${REAL_ROOTDEV}' to '${REAL_ROOTDIR}'."
}

blockdev_mount() {
	local dev="${1}"
	local dir="${2}"
	local rw=0
	local mount_opt="ro"
	if [ ! -z "${3}" -a "${3}" = "1" ]; then
		rw="1"
	fi

	local rw_info="read-only"
	if [ "${rw}" = "1" ]; then
		rw_info="read-write"
		mount_opt="rw"
	fi
	
	# hm, this can be helpful
	# mount_opt="${mount_opt},noatime"

	msg_info "Mounting device '${TERM_LRED}${dev}${TERM_RESET}' to '${TERM_YELLOW}${2}${TERM_RESET}' ${TERM_BOLD}${rw_info}${TERM_RESET}."
	mount -o ${mount_opt} "${dev}" "${dir}" || die "Unable to mount ${dev} to ${dir}."
}

tmpfs_mount() {
	local dir="${1}"
	local size="${2}"
	test -z "${size}" && size="${TMPFS_SIZE}"
	test ! -d "${dir}" && die "Unable to mount tmpfs to nonexisting directory '${dir}'"

	# mount it
	msg_info "Mounting ${TERM_YELLOW}tmpfs${TERM_RESET} size ${TERM_LGREEN}${size}${TERM_RESET}, type ${TERM_LGREEN}${TMPFS_TYPE}${TERM_RESET} filesystem to '${TERM_LRED}${dir}${TERM_RESET}'"
	mount -t ${TMPFS_TYPE} -o noatime,rw,size=${size} none "${dir}" || die "Unable to mount tmpfs."
}

blockdev_wait() {
	local dev="${1}"
	local time="${2}"
	local fatal="${3}"

	test -z "${time}" && time="${BLOCKDEV_TIMEOUT}"
	test -z "${fatal}" && fatal="1"

	local i=0
	echo -ne "${TERM_YELLOW}WARNING:${TERM_RESET} Waiting for device '${TERM_LRED}${dev}${TERM_RESET}' (${time} sec): "
	while [ ${i} -lt ${time} -a ! -b "${dev}" ]; do
		i=$((i + 1))
		echo -n "."
		sleep 1
	done

	if [ -b "${dev}" ]; then
		echo " OK."
	else
		echo " FAILED."
		if [ "${fatal}" = "1" ]; then
			die "Block device '${dev}' is not available."
		fi
		return 1
	fi

	return 0
}

# checks if plugin is loaded
plugin_loaded() {
	echo "${LOADED_PLUGINS}" | egrep " ${1} " >/dev/null 2>&1
	return $?
}

# checks if plugin is initialized
plugin_initialized() {
	plugin_${1}_initialized
}

# initialize plugin
plugin_init() {
	if ! plugin_initialized "${1}"; then
		plugin_${1}_init
	fi
}

# require and initialize plugin
plugin_require() {
	plugin_loaded "${1}" || die "Plugin '${TERM_LRED}${1}${TERM_RESET}' is not loaded."
	plugin_init "${1}"
}

failback_shell() {
	# hm, mount pseudo filesystems
	pseudo_fs_mount

	# start syslogd
	syslog_start
	
	# print some nice instructions
	msg_warn ""
	msg_warn "             ${TERM_LBLUE}Interactive failback shell${TERM_RESET}"
	msg_warn ""
	msg_warn "Type:"
	msg_warn "       '${TERM_LRED}exit${TERM_RESET}' to continue booting process"
	msg_warn "              or to crash kernel if you see"
	msg_warn "              this message becouse of initrd"
	msg_warn "              fatal error ;)"
	msg_warn ""
	msg_warn "       '${TERM_LRED}reboot${TERM_RESET}' to reboot system"
	msg_warn ""
	msg_warn "... or any other available system command if you want to do some"
	msg_warn "maintenance tasks from this initrd failback shell."
	msg_warn ""
	msg_warn "If you want to start ${TERM_LGREEN}network${TERM_RESET}, type:"
	msg_warn ""
	msg_warn "    ${TERM_LRED}udhcpc${TERM_RESET} -i ${TERM_YELLOW}<network device>${TERM_RESET}"
	msg_warn ""
	msg_warn "Good luck ;)"
	msg_warn ""

	/bin/ash
}

boot() {
	# deinitialize script
	# deinit

	echo -e "${TERM_YELLOW}##############################################${TERM_RESET}"
	echo -e "${TERM_YELLOW}#      Exiting initrd; starting real OS      #${TERM_RESET}"
	echo -e "${TERM_YELLOW}##############################################${TERM_RESET}"

	if [ "${INITRD_TYPE}" = "initrd" ]; then
		boot_initrd
	else
		boot_initramfs
	fi
}

boot_initrd() {
	msg_info "Booting ${TERM_LGREEN}INITRD${TERM_RESET}."

	# deinitialize script
	deinit_full

	# chdir to mounted real root directory
	cd "${REAL_ROOTDIR}" || die "Unable to enter directory ${REAL_ROOTDIR}"

	# check for real init existence
	test ! -x "${REAL_ROOTDIR}/${REAL_INIT}" -o ! -f "${REAL_ROOTDIR}/${REAL_INIT}" && die "Real init '${TERM_LRED}${REAL_INIT}${TERM_RESET}' does not exist on real root filesystem or is not executable."

	local need_rw_mount="0"
	
	test ! -d "${INITRD_DIR}" && need_rw_mount="1"
	test ! -e "dev/console"  && need_rw_mount="1"
	test ! -e "dev/console"  && need_rw_mount="1"

	if [ "${need_rw_mount}" != "0" ]; then
		msg_warn "Some important files/directories are missing on real filesystem."
		msg_warn "Remounting real filesystem read-write."
		mount -o remount,rw "${REAL_ROOTDIR}" || die "Unable to remount real root filesystem rw."

		# check for initrd dir
		if [ ! -d "${INITRD_DIR}" ]; then
			msg_warn "Initrd dir '${INITRD_DIR}' does not exist on real root filesystem, trying to create."

			# seems like that initrd dir does not exist,
			# create it...
			# maybe there is a file
			rm -f "${INITRD_DIR}" >/dev/null 2>&1
		
			# try to create directory
			mkdir "${INITRD_DIR}" || die "Unable to create initrd dir '${INITRD_DIR}' on real root filesystem."
		fi

		# check for special devices...
		if [ ! -e "dev/console" ]; then
			msg_warn "Special device /dev/console does not exist on real root filesystem, trying to create."
			mknod -m 640 dev/console c 5 1 || die "Unable to create missing device /dev/console."
		fi

		if [ ! -e "dev/null" ]; then
			msg_warn "Special device /dev/null does not exist on real root filesystem, trying to create."
			mknod -m 666 dev/null c 1 3 || die "Unable to create missing device /dev/null."
		fi

		# remount filesystem readonly
		msg_warn "Remounting real filesystem read-only again."
		mount -o remount,ro "${REAL_ROOTDIR}" >/dev/null 2>&1
	fi
	
	# change root
	msg_debug "pivot_root . ${INITRD_DIR}"
	pivot_root . "${INITRD_DIR}" || die "Unable to swap root directory: pivot_root failed."
	
	# this is it, chroot && run real init...
	msg_debug "exec chroot . ${REAL_INIT} < dev/console > dev/console"
	my_exec chroot . ${REAL_INIT} < dev/console > dev/console 2>&1
}

boot_initramfs() {
	msg_info "Booting ${TERM_LGREEN}INITRAMFS${TERM_RESET}; my PID: $$."

	# deinit
	deinit

	# move proc && sys
	if [ -d "${REAL_ROOTDIR}/proc" ]; then
		msg_debug "Moving mount /proc => ${REAL_ROOTDIR}/proc"
		mount --move /proc "${REAL_ROOTDIR}/proc"
	fi
	if [ -d "${REAL_ROOTDIR}/sys" ]; then
		msg_debug "Moving mount /sys => ${REAL_ROOTDIR}/sys"
		mount --move /sys "${REAL_ROOTDIR}/sys"
	fi

	if [ -x "/sbin/switch_root" ]; then
		# rm -f "/init"
 		my_exec /sbin/switch_root "${REAL_ROOTDIR}" "${REAL_INIT}"
	else
		die "switch_root is not available."
	fi
}

##############################################
#                   MAIN                     #
##############################################

echo -e "${TERM_YELLOW}##############################################${TERM_RESET}"
echo -e "${TERM_YELLOW}#     Starting initrd image version ${VERSION}     #${TERM_RESET}"
echo -e "${TERM_YELLOW}##############################################${TERM_RESET}"

# initialize scrip,
# kernel modules, plugins
# and stuff..
init

# maybe user asked for failback console
if [ "${FAILBACK_MODE}" = "1" ]; then
	failback_shell
fi

# initialize & mount root filesystem
init_rootfs

# ok, so far we should have root filesystem mounted
# on ${REAL_ROOTDIR}
# Time to boot REAL operating system from it ;)
boot

# fall back to shell if init failed...
die "Real init '${REAL_INIT} on device '${REAL_ROOTDEV}' mounted on '${REAL_ROOTDIR} failed to execute properly."

# EOF
