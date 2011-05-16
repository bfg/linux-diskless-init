#
# WHAT: unknown root device plugin.
# PURPOSE: when unknown root device should be mounted
#          it just shows fatal error message
#

#
# Id: $Id: unknown.inc.sh 36 2006-10-19 07:22:37Z bfg $
# Last changed on: $LastChangedDate: 2006-10-19 09:22:37 +0200 (Thu, 19 Oct 2006) $
# Last changed by: $LastChangedBy: bfg $
#

##############################################
#         PLUGIN SPECIFIC GLOBALS            #
##############################################

# all globals from linuxrc script are visible
# also in plugins...
#
# Every plugin can have also it's own "private"
# variables, but they must be named in the
# the following way:
#
# $_<PLUGIN_NAME>_VARIABLE_NAME
#

# this is sample variable
_UNKNOWN_SAMPLE_VAR=1

##############################################
#           "PUBLIC" FUNCTIONS               #
##############################################

# this plugin always initializes on load silently ;)
plugin_unknown_init_onload() {
	return 0
}

# ... is always initialized ;)
plugin_unknown_initialized() {
	return 0
}

# ... always initializes without problem ;)
plugin_unknown_init() {
	return 0
}

# ...can never handle any rootdev
plugin_unknown_can_handle_rootdev() {
	return 1
}

# well, in fact, it cannot mount anything eighter ;)
plugin_unknown_mount() {
	die "Sorry, i don't know how to mount '${1}'..."
}

# ... and ofcourse always deinitializes without problem ;)
plugin_unknown_deinit() {
	return 0
}

##############################################
#           "PRIVATE" FUNCTIONS              #
##############################################

# each plugin can have it's own "private"
# functions, but they MUST NOT INTERFERE
# with namespace of other plugins...
#
# each function must be named in the following
# way:
#
# _plugin_<PLUGIN_NAME>_<FUNCTION_NAME>

_plugin_unknown_sample_private_function() {
	return 0
}

# EOF