#!/usr/bin/env bash
# shellcheck shell=bash
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202510311148-git
# @@Author           :  Jason Hempstead
# @@Contact          :  jason@casjaysdev.pro
# @@License          :  LICENSE.md
# @@ReadME           :  02-named.sh --help
# @@Copyright        :  Copyright: (c) 2025 Jason Hempstead, Casjays Developments
# @@Created          :  Friday, Oct 31, 2025 11:48 EDT
# @@File             :  02-named.sh
# @@Description      :
# @@Changelog        :  New script
# @@TODO             :  Better documentation
# @@Other            :
# @@Resource         :
# @@Terminal App     :  no
# @@sudo/root        :  no
# @@Template         :  other/start-service
# - - - - - - - - - - - - - - - - - - - - - - - - -
# shellcheck disable=SC1001,SC1003,SC2001,SC2003,SC2016,SC2031,SC2120,SC2155,SC2199,SC2317,SC2329
# - - - - - - - - - - - - - - - - - - - - - - - - -
set -e
# - - - - - - - - - - - - - - - - - - - - - - - - -
# run trap command on exit
trap 'retVal=$?; echo "❌ Fatal error occurred: Exit code $retVal at line $LINENO in command: $BASH_COMMAND"; kill -TERM 1' ERR
trap 'retVal=$?;if [ "$SERVICE_IS_RUNNING" != "yes" ] && [ -f "$SERVICE_PID_FILE" ]; then rm -Rf "$SERVICE_PID_FILE"; fi;exit $retVal' SIGINT SIGTERM SIGPWR
# - - - - - - - - - - - - - - - - - - - - - - - - -
SCRIPT_FILE="$0"
SERVICE_NAME="named"
SCRIPT_NAME="$(basename -- "$SCRIPT_FILE" 2>/dev/null)"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Function to exit appropriately based on context
__script_exit() {
	local exit_code="${1:-0}"
	if [ "${BASH_SOURCE[0]}" != "${0}" ]; then
		# Script is being sourced - use return
		return "$exit_code"
	else
		# Script is being executed - use exit
		exit "$exit_code"
	fi
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Exit if service is disabled
[ -z "$NAMED_APPNAME_ENABLED" ] || if [ "$NAMED_APPNAME_ENABLED" != "yes" ]; then export SERVICE_DISABLED="$SERVICE_NAME" && __script_exit 0; fi
# - - - - - - - - - - - - - - - - - - - - - - - - -
# setup debugging - https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html
[ -f "/config/.debug" ] && [ -z "$DEBUGGER_OPTIONS" ] && export DEBUGGER_OPTIONS="$(<"/config/.debug")" || DEBUGGER_OPTIONS="${DEBUGGER_OPTIONS:-}"
{ [ "$DEBUGGER" = "on" ] || [ -f "/config/.debug" ]; } && echo "Enabling debugging" && set -xo pipefail -x$DEBUGGER_OPTIONS && export DEBUGGER="on" || set -o pipefail
# - - - - - - - - - - - - - - - - - - - - - - - - -
export PATH="/usr/local/etc/docker/bin:/usr/local/bin:/usr/bin:/usr/sbin:/bin:/sbin"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# import the functions file
if [ -f "/usr/local/etc/docker/functions/entrypoint.sh" ]; then
	. "/usr/local/etc/docker/functions/entrypoint.sh"
fi
# - - - - - - - - - - - - - - - - - - - - - - - - -
# import variables
for set_env in "/root/env.sh" "/usr/local/etc/docker/env"/*.sh "/config/env"/*.sh; do
	[ -f "$set_env" ] && . "$set_env"
done
# - - - - - - - - - - - - - - - - - - - - - - - - -
# exit if __start_init_scripts function hasn't been Initialized
if [ ! -f "/run/__start_init_scripts.pid" ]; then
	echo "__start_init_scripts function hasn't been Initialized" >&2
	SERVICE_IS_RUNNING="no"
	__script_exit 1
fi
# Clean up any stale PID file for this service on startup
if [ -n "$SERVICE_NAME" ] && [ -f "/run/init.d/$SERVICE_NAME.pid" ]; then
	old_pid=$(cat "/run/init.d/$SERVICE_NAME.pid" 2>/dev/null)
	if [ -n "$old_pid" ] && ! kill -0 "$old_pid" 2>/dev/null; then
		echo "🧹 Removing stale PID file for $SERVICE_NAME"
		rm -f "/run/init.d/$SERVICE_NAME.pid"
	fi
fi
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Custom functions
__rndc_key() { grep -s 'key "rndc-key" ' /etc/named.conf | grep -v 'KEY_RNDC' | sed 's|.*secret ||g;s|"||g;s|;.*||g' | grep '^' || return 1; }
__dhcp_key() { grep -s 'key "dhcp-key" ' /etc/named.conf | grep -v 'KEY_DHCP' | sed 's|.*secret ||g;s|"||g;s|;.*||g' | grep '^' || return 1; }
__certbot_key() { grep -s 'key "certbot" ' /etc/named.conf | grep -v 'KEY_CERTBOT' | sed 's|.*secret ||g;s|"||g;s|;.*||g' | grep '^' || return 1; }
__backup_key() { grep -s 'key "backup-key" ' /etc/named.conf | grep -v 'KEY_BACKUP' | sed 's|.*secret ||g;s|"||g;s|;.*||g' | grep '^' || return 1; }
__tsig_key() { tsig-keygen -a hmac-${1:-sha512} | grep 'secret' | sed 's|.*secret "||g;s|"||g;s|;||g' | grep '^' || echo 'I665bFnjoPMB9EmEUl5uZ+o7e4ryM02irerkCkLJiSPJJYJBvBHSXCauNn44zY2C318DSWRcCx+tf8WESYwgKQ=='; }
__check_dig() { dig "${1:-localhost}" "${2:-A}" | grep 'IN' | grep '[0-9][0-9]' | sed 's|.*A||g' | sed "s/^[ \t]*//" || return 2; }
__get_dns_record() { grep '^@' "/data/bind/zones/$1.zone" | grep 'IN' | grep ' A ' | sed 's|.*A||g;s|;.*||g;s/^[ \t]*//' || return 2; }
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Script to execute
START_SCRIPT="/usr/local/etc/docker/exec/$SERVICE_NAME"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Reset environment before executing service
RESET_ENV="no"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Set webroot
WWW_ROOT_DIR="/usr/local/share/httpd/default"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Default predefined variables
DATA_DIR="/data/bind"   # set data directory
CONF_DIR="/config/bind" # set config directory
# - - - - - - - - - - - - - - - - - - - - - - - - -
# set the containers etc directory
ETC_DIR="/etc/bind"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# set the var dir
VAR_DIR=""
# - - - - - - - - - - - - - - - - - - - - - - - - -
TMP_DIR="/tmp/bind"       # set the temp dir
RUN_DIR="/run/bind"       # set scripts pid dir
LOG_DIR="/data/logs/bind" # set log directory
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Set the working dir
WORK_DIR=""
# - - - - - - - - - - - - - - - - - - - - - - - - -
# port which service is listening on
SERVICE_PORT="53"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# User to use to launch service - IE: postgres
RUNAS_USER="root" # normally root
# - - - - - - - - - - - - - - - - - - - - - - - - -
# User and group in which the service switches to - IE: nginx,apache,mysql,postgres
#SERVICE_USER="bind"  # execute command as another user
#SERVICE_GROUP="bind" # Set the service group
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Set password length
RANDOM_PASS_USER=""
RANDOM_PASS_ROOT=""
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Set user and group ID
SERVICE_UID="0" # set the user id
SERVICE_GID="0" # set the group id
# - - - - - - - - - - - - - - - - - - - - - - - - -
# execute command variables - keep single quotes variables will be expanded later
EXEC_CMD_BIN='named'                                       # command to execute
EXEC_CMD_ARGS='-f -u $SERVICE_USER -c $ETC_DIR/named.conf' # command arguments
EXEC_PRE_SCRIPT=''                                         # execute script before
SERVICE_USES_PID=''                                        # Set to no if the service is not running otherwise leave blank
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Is this service a web server
IS_WEB_SERVER="no"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Is this service a database server
IS_DATABASE_SERVICE="no"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Does this service use a database server
USES_DATABASE_SERVICE="no"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Set defualt type - [custom,sqlite,redis,postgres,mariadb,mysql,couchdb,mongodb,supabase]
DATABASE_SERVICE_TYPE="sqlite"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Show message before execute
PRE_EXEC_MESSAGE=""
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Set the wait time to execute __post_execute function - minutes
POST_EXECUTE_WAIT_TIME="1"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Update path var
PATH="$PATH:."
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Lets get containers ip address
IP4_ADDRESS="$(__get_ip4)"
IP6_ADDRESS="$(__get_ip6)"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Where to save passwords to
ROOT_FILE_PREFIX="/config/secure/auth/root" # directory to save username/password for root user
USER_FILE_PREFIX="/config/secure/auth/user" # directory to save username/password for normal user
# - - - - - - - - - - - - - - - - - - - - - - - - -
# root/admin user info password/random]
root_user_name="${NAMED_ROOT_USER_NAME:-}" # root user name
root_user_pass="${NAMED_ROOT_PASS_WORD:-}" # root user password
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Normal user info [password/random]
user_name="${NAMED_USER_NAME:-}"      # normal user name
user_pass="${NAMED_USER_PASS_WORD:-}" # normal user password
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Load variables from config
[ -f "/config/env/named.script.sh" ] && . "/config/env/named.script.sh" # Generated by my dockermgr script
[ -f "/config/env/named.sh" ] && . "/config/env/named.sh"               # Overwrite the variabes
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Additional predefined variables

# - - - - - - - - - - - - - - - - - - - - - - - - -
# Additional variables
DNS_SERIAL="$(date +'%Y%m%d%S')"
DNS_ZONE_FILE="$ETC_DIR/zones.conf"
KEY_DHCP="${KEY_DHCP:-$(__dhcp_key || __tsig_key sha512)}"
KEY_RNDC="${KEY_RNDC:-$(__rndc_key || __tsig_key sha512)}"
KEY_BACKUP="${KEY_BACKUP:-$(__backup_key || __tsig_key sha512)}"
KEY_CERTBOT="${KEY_CERTBOT:-$(__certbot_key || __tsig_key sha512)}"
DNS_TYPE="${DNS_TYPE:-primary}"
DNS_REMOTE_SERVER="${DNS_REMOTE_SERVER:-}"
DNS_SERVER_PRIMARY="${DNS_SERVER_PRIMARY:-}"
DNS_SERVER_SECONDARY="${DNS_SERVER_SECONDARY:-}"
DNS_SERVER_TRANSFER_IP="${DNS_SERVER_TRANSFER_IP:-}"
DNS_SERVER_SECONDARY="$(echo "${DNS_SERVER_SECONDARY:-$DNS_SERVER_TRANSFER_IP}" | sed 's|,|;|g;s| |; |g;s|;$||g;s| $||g')"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Specifiy custom directories to be created
ADD_APPLICATION_FILES=""
ADD_APPLICATION_DIRS=""
# - - - - - - - - - - - - - - - - - - - - - - - - -
APPLICATION_FILES="$LOG_DIR/$SERVICE_NAME.log"
APPLICATION_DIRS="$ETC_DIR $CONF_DIR $DATA_DIR $LOG_DIR $TMP_DIR $RUN_DIR $VAR_DIR"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Additional config dirs - will be Copied to /etc/$name
ADDITIONAL_CONFIG_DIRS=""
# - - - - - - - - - - - - - - - - - - - - - - - - -
# define variables that need to be loaded into the service - escape quotes - var=\"value\",other=\"test\"
CMD_ENV=""
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Overwrite based on file/directory
[ -f "$CONF_DIR/secrets/rndc.key" ] && KEY_RNDC="$(grep -vE '#|^$' "$CONF_DIR/secrets/rndc.key" | sed 's| ||g' | head -n1 | grep '^' || echo "$KEY_RNDC")"
[ -f "$CONF_DIR/secrets/dhcp.key" ] && KEY_DHCP="$(grep -vE '#|^$' "$CONF_DIR/secrets/dhcp.key" | sed 's| ||g' | head -n1 | grep '^' || echo "$KEY_DHCP")"
[ -f "$CONF_DIR/secrets/backup.key" ] && KEY_BACKUP="$(grep -vE '#|^$' "$CONF_DIR/secrets/backup.key" | sed 's| ||g' | head -n1 | grep '^' || echo "$KEY_BACKUP")"
[ -f "$CONF_DIR/secrets/certbot.key" ] && KEY_CERTBOT="$(grep -vE '#|^$' "$CONF_DIR/secrets/certbot.key" | sed 's| ||g' | head -n1 | grep '^' || echo "$KEY_CERTBOT")"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Per Application Variables or imports
[ -f "$CONF_DIR/named.conf" ] && NAMED_CONFIG_FILE="$CONF_DIR/named.conf" && NAMED_CONFIG_COPY="yes" || NAMED_CONFIG_FILE="$ETC_DIR/named.conf"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Custom commands to run before copying to /config
__run_precopy() {
	# Define environment
	local hostname=${HOSTNAME}
	[ -d "/run/healthcheck" ] || mkdir -p "/run/healthcheck"
	# Define actions/commands
	[ -d "/data/named" ] && [ ! -d "$DATA_DIR" ] && mv -fv "/data/named" "$DATA_DIR"
	[ -d "/config/named" ] && [ ! -d "$CONF_DIR" ] && mv -fv "/config/named" "$CONF_DIR"
	# allow custom functions
	if builtin type -t __run_precopy_local | grep -q 'function'; then __run_precopy_local; fi
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Custom prerun functions - IE setup WWW_ROOT_DIR
__execute_prerun() {
	# Define environment
	local hostname=${HOSTNAME}
	# Define actions/commands

	# allow custom functions
	if builtin type -t __execute_prerun_local | grep -q 'function'; then __execute_prerun_local; fi
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Run any pre-execution checks
__run_pre_execute_checks() {
	# Set variables
	local exitStatus=0
	local pre_execute_checks_MessageST="Running preexecute check for $SERVICE_NAME"   # message to show at start
	local pre_execute_checks_MessageEnd="Finished preexecute check for $SERVICE_NAME" # message to show at completion
	__banner "$pre_execute_checks_MessageST"
	# Put command to execute in parentheses
	{
		chown -Rf "$SERVICE_USER":"$SERVICE_GROUP" $ETC_DIR $VAR_DIR $LOG_DIR
		if named-checkconf -z $NAMED_CONFIG_FILE &>/dev/null; then
			echo "named-checkconf has succeeded"
			return 0
		else
			echo "named-checkconf has failed:"
			named-checkconf -z $NAMED_CONFIG_FILE
			return 1
		fi
	}
	exitStatus=$?
	__banner "$pre_execute_checks_MessageEnd: Status $exitStatus"

	# show exit message
	if [ $exitStatus -ne 0 ]; then
		echo "The pre-execution check has failed" >&2
		[ -f "$SERVICE_PID_FILE" ] && rm -Rf "$SERVICE_PID_FILE"
		__script_exit 1
	fi
	# allow custom functions
	if builtin type -t __run_pre_execute_checks_local | grep -q 'function'; then __run_pre_execute_checks_local; fi
	# exit function
	return $exitStatus
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
# use this function to update config files - IE: change port
__update_conf_files() {
	local exitCode=0                                               # default exit code
	local sysname="${SERVER_NAME:-${FULL_DOMAIN_NAME:-$HOSTNAME}}" # set hostname
	# - - - - - - - - - - - - - - - - - - - - - - - - -
	# delete files
	#__rm ""

	# - - - - - - - - - - - - - - - - - - - - - - - - -
	# custom commands
	mkdir -p "$CONF_DIR/keys" "$CONF_DIR/secrets"
	mkdir -p "$ETC_DIR/keys" "$ETC_DIR/secrets" "$VAR_DIR/primary" "$VAR_DIR/secondary" "$VAR_DIR/stats" "$VAR_DIR/dynamic"
	for logfile in debug.run querylog.log security.log xfer.log update.log notify.log client.log default.log general.log database.log; do
		touch "$LOG_DIR/$logfile"
		chmod -Rf 777 "$logfile"
	done
	if [ -n "$DNS_SERVER_TRANSFER_IP" ]; then
		for ip in ${DNS_SERVER_TRANSFER_IP//;/ }; do
			secondary_ip+="$ip; "
		done
		DNS_SERVER_TRANSFER_IP="$secondary_ip"
	fi
	# - - - - - - - - - - - - - - - - - - - - - - - - -
	# replace variables
	__replace "REPLACE_KEY_RNDC" "$KEY_RNDC" "$ETC_DIR/rndc.key"
	__replace "REPLACE_KEY_RNDC" "$KEY_RNDC" "$NAMED_CONFIG_FILE"
	__replace "REPLACE_KEY_DHCP" "$KEY_DHCP" "$NAMED_CONFIG_FILE"
	__replace "REPLACE_KEY_BACKUP" "$KEY_BACKUP" "$NAMED_CONFIG_FILE"
	__replace "REPLACE_KEY_CERTBOT" "$KEY_CERTBOT" "$NAMED_CONFIG_FILE"
	__find_replace "REPLACE_DNS_SERIAL" "$DNS_SERIAL" "$DATA_DIR/primary"
	__find_replace "REPLACE_DNS_SERIAL" "$DNS_SERIAL" "$DATA_DIR/secondary"
	if [ -n "$DNS_SERVER_TRANSFER_IP" ]; then
		__replace "REPLACE_DNS_SERVER_TRANSFER_IP" "$DNS_SERVER_TRANSFER_IP" "$NAMED_CONFIG_FILE"
	else
		sed -i '/REPLACE_DNS_SERVER_TRANSFER_IP/d' "$NAMED_CONFIG_FILE"
	fi
	# - - - - - - - - - - - - - - - - - - - - - - - - -
	# define actions
	if [ -f "$CONF_DIR/custom.conf" ]; then
		cp -f "$CONF_DIR/custom.conf" "$NAMED_CONFIG_FILE"
	elif [ -f "$ETC_DIR/custom.conf" ]; then
		cp -f "$ETC_DIR/custom.conf" "$NAMED_CONFIG_FILE"
	fi
	[ -n "$KEY_RNDC" ] && echo "$KEY_RNDC" >"$CONF_DIR/secrets/rndc.key"
	[ -n "$KEY_DHCP" ] && echo "$KEY_DHCP" >"$CONF_DIR/secrets/dhcp.key"
	[ -n "$KEY_BACKUP" ] && echo "$KEY_BACKUP" >"$CONF_DIR/secrets/backup.key"
	[ -n "$KEY_CERTBOT" ] && echo "$KEY_CERTBOT" >"$CONF_DIR/secrets/certbot.key"
	[ -f "$VAR_DIR/root.cache" ] || cp -Rf "/usr/local/share/bind/data/root.cache" "$VAR_DIR/root.cache"
	# allow custom functions
	if builtin type -t __update_conf_files_local | grep -q 'function'; then __update_conf_files_local; fi
	# exit function
	return $exitCode
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
# function to run before executing
__pre_execute() {
	local exitCode=0                                               # default exit code
	local sysname="${SERVER_NAME:-${FULL_DOMAIN_NAME:-$HOSTNAME}}" # set hostname
	# execute if directories is empty
	# __is_dir_empty "$CONF_DIR" && true
	# - - - - - - - - - - - - - - - - - - - - - - - - -
	# define actions to run after copying to /config
	zone_files="$(find "$DATA_DIR/zones/" -type f | wc -l)"
	if [ $zone_files = 0 ] && [ ! -f "$VAR_DIR/primary/$HOSTNAME.zone" ]; then
		cat <<EOF >>"$DNS_ZONE_FILE"
#  ********** begin $HOSTNAME **********
zone "$HOSTNAME" {
    type master;
    notify yes;
    allow-transfer { any; key "backup-key"; trusted; };
    allow-update {key "certbot."; key "dhcp-key"; trusted; };
    file "$VAR_DIR/primary/$file_name";
};
#  ********** end $HOSTNAME **********

EOF

		cat <<EOF | tee "$VAR_DIR/primary/$HOSTNAME.zone" &>/dev/null
; config for $HOSTNAME
@                         IN  SOA     $HOSTNAME. root.$HOSTNAME. ( $DNS_SERIAL 10800 3600 1209600 38400)
                          IN  NS      $HOSTNAME.
$HOSTNAME.                IN  A       $CONTAINER_IP4_ADDRESS

EOF
	fi
	#
	if [ -d "$DATA_DIR/zones" ]; then
		for dns_file in "$DATA_DIR/zones"/*; do
			file_name="$(basename "$dns_file")"
			domain_name="$(grep -Rs '\$ORIGIN' "$dns_file" | awk '{print $NF}' | sed 's|.$||g')"
			if [ -f "$dns_file" ]; then
				if [ -n "$domain_name" ] && ! grep -qs "$domain_name" "$NAMED_CONFIG_FILE"; then
					if [ "$DNS_TYPE" = "secondary" ]; then
						[ -f "$VAR_DIR/secondary/$file_name" ] || echo "" >"$VAR_DIR/secondary/$file_name"
						cat <<EOF >>"$DNS_ZONE_FILE"
#  ********** begin $domain_name **********
zone "$domain_name" {
    type slave;
    masters { $DNS_SERVER_PRIMARY; };
    file "$VAR_DIR/secondary/$file_name";
};
#  ********** end $domain_name **********

EOF
					else
						cp -Rf "$dns_file" "$VAR_DIR/primary/$file_name"
						if [ -n "$DNS_SERVER_SECONDARY" ]; then
							cat <<EOF >>"$DNS_ZONE_FILE"
#  ********** begin $domain_name **********
zone "$domain_name" {
    type master;
    notify yes;
    also-notify { $DNS_SERVER_SECONDARY; };
    allow-transfer { any; key "backup-key"; trusted; };
    allow-update { key "certbot."; key "dhcp-key"; trusted; key "ddns-key"; };
    file "$VAR_DIR/primary/$file_name";
};
#  ********** end $domain_name **********

EOF
						else
							cat <<EOF >>"$DNS_ZONE_FILE"
#  ********** begin $domain_name **********
zone "$domain_name" {
    type master;
    notify yes;
    allow-transfer { any; key "backup-key"; trusted; };
    allow-update { key "certbot."; key "dhcp-key"; trusted; key "ddns-key"; };
    file "$VAR_DIR/primary/$file_name";
};
#  ********** end $domain_name **********

EOF
						fi
					fi
					grep -qs "$domain_name" "$DNS_ZONE_FILE" && echo "Added $domain_name to $DNS_ZONE_FILE"
				fi
			fi
		done
	fi

	if [ -d "$DATA_DIR/remote" ]; then
		for dns_file in "$DATA_DIR/remote"/*; do
			if [ -s "$dns_file" ]; then
				file_name="$(basename "$dns_file")"
				domain_name="$(basename "${dns_file%.*}")"
				if [ -n "$domain_name" ]; then
					cat "$dns_file" | sed 's|REPLACE_VAR_DIR|'$VAR_DIR'|g' >>"$DNS_ZONE_FILE"
					grep -qs "$domain_name" "$DNS_ZONE_FILE" && echo "Secondary $domain_name to $DNS_ZONE_FILE"
				else
					echo "Failed to get domain name from $dns_file" | tee -a "$LOG_DIR/init.txt" >&2
				fi
			fi
		done
	fi
	[ "$NAMED_CONFIG_COPY" = "yes" ] && cp -Rf "$NAMED_CONFIG_FILE" "$ETC_DIR/named.conf" || cp -Rf "$NAMED_CONFIG_FILE" "$CONF_DIR/named.conf"
	# - - - - - - - - - - - - - - - - - - - - - - - - -
	# unset unneeded variables
	unset sysname
	# Lets wait a few seconds before continuing
	sleep 2
	# allow custom functions
	if builtin type -t __pre_execute_local | grep -q 'function'; then __pre_execute_local; fi
	# exit function
	return $exitCode
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
# function to run after executing
__post_execute() {
	local pid=""                                                    # init pid var
	local retVal=0                                                  # set default exit code
	local ctime=${POST_EXECUTE_WAIT_TIME:-1}                        # how long to wait before executing
	local waitTime=$((ctime * 60))                                  # convert minutes to seconds
	local postMessageST="Running post commands for $SERVICE_NAME"   # message to show at start
	local postMessageEnd="Finished post commands for $SERVICE_NAME" # message to show at completion
	# wait
	sleep $waitTime
	# execute commands after waiting
	(
		# show message
		__banner "$postMessageST"
		# commands to execute
		sleep 5
		# show exit message
		__banner "$postMessageEnd: Status $retVal"
	) 2>"/dev/stderr" | tee -p -a "/data/logs/init.txt" &
	pid=$!
	ps ax | awk '{print $1}' | grep -v grep | grep -q "$execPid$" && retVal=0 || retVal=10
	# allow custom functions
	if builtin type -t __post_execute_local | grep -q 'function'; then __post_execute_local; fi
	# exit function
	return $retVal
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
# use this function to update config files - IE: change port
__pre_message() {
	local exitCode=0
	[ -n "$PRE_EXEC_MESSAGE" ] && eval echo "$PRE_EXEC_MESSAGE"
	# execute commands

	# allow custom functions
	if builtin type -t __pre_message_local | grep -q 'function'; then __pre_message_local; fi
	# exit function
	return $exitCode
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
# use this function to setup ssl support
__update_ssl_conf() {
	local exitCode=0
	local sysname="${SERVER_NAME:-${FULL_DOMAIN_NAME:-$HOSTNAME}}" # set hostname
	# execute commands

	# allow custom functions
	if builtin type -t __update_ssl_conf_local | grep -q 'function'; then __update_ssl_conf_local; fi
	# set exitCode
	return $exitCode
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
__create_service_env() {
	local exitCode=0
	if [ ! -f "/config/env/${SERVICE_NAME:-$SCRIPT_NAME}.sh" ]; then
		cat <<EOF | tee -p "/config/env/${SERVICE_NAME:-$SCRIPT_NAME}.sh" &>/dev/null
# - - - - - - - - - - - - - - - - - - - - - - - - -
# root/admin user info [password/random]
#ENV_ROOT_USER_NAME="${ENV_ROOT_USER_NAME:-$NAMED_ROOT_USER_NAME}"   # root user name
#ENV_ROOT_USER_PASS="${ENV_ROOT_USER_NAME:-$NAMED_ROOT_PASS_WORD}"   # root user password
#root_user_name="${ENV_ROOT_USER_NAME:-$root_user_name}"                              #
#root_user_pass="${ENV_ROOT_USER_PASS:-$root_user_pass}"                              #
# - - - - - - - - - - - - - - - - - - - - - - - - -
#Normal user info [password/random]
#ENV_USER_NAME="${ENV_USER_NAME:-$NAMED_USER_NAME}"                  #
#ENV_USER_PASS="${ENV_USER_PASS:-$NAMED_USER_PASS_WORD}"             #
#user_name="${ENV_USER_NAME:-$user_name}"                                             # normal user name
#user_pass="${ENV_USER_PASS:-$user_pass}"                                             # normal user password

EOF
	fi
	if [ ! -f "/config/env/${SERVICE_NAME:-$SCRIPT_NAME}.local.sh" ]; then
		# - - - - - - - - - - - - - - - - - - - - - - - - -
		__run_precopy_local() { true; }
		# - - - - - - - - - - - - - - - - - - - - - - - - -
		__execute_prerun_local() { true; }
		# - - - - - - - - - - - - - - - - - - - - - - - - -
		__run_pre_execute_checks_local() { true; }
		# - - - - - - - - - - - - - - - - - - - - - - - - -
		__update_conf_files_local() { true; }
		# - - - - - - - - - - - - - - - - - - - - - - - - -
		__pre_execute_local() { true; }
		# - - - - - - - - - - - - - - - - - - - - - - - - -
		__post_execute_local() { true; }
		# - - - - - - - - - - - - - - - - - - - - - - - - -
		__pre_message_local() { true; }
		# - - - - - - - - - - - - - - - - - - - - - - - - -
		__update_ssl_conf_local() { true; }
		# - - - - - - - - - - - - - - - - - - - - - - - - -
	fi
	__file_exists_with_content "/config/env/${SERVICE_NAME:-$SCRIPT_NAME}.sh" || exitCode=$((exitCode + 1))
	__file_exists_with_content "/config/env/${SERVICE_NAME:-$SCRIPT_NAME}.local.sh" || exitCode=$((exitCode + 1))
	return $exitCode
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
# script to start server
__run_start_script() {
	local runExitCode=0
	local workdir="$(eval echo "${WORK_DIR:-}")"                   # expand variables
	local cmd="$(eval echo "${EXEC_CMD_BIN:-}")"                   # expand variables
	local args="$(eval echo "${EXEC_CMD_ARGS:-}")"                 # expand variables
	local name="$(eval echo "${EXEC_CMD_NAME:-}")"                 # expand variables
	local pre="$(eval echo "${EXEC_PRE_SCRIPT:-}")"                # expand variables
	local extra_env="$(eval echo "${CMD_ENV//,/ }")"               # expand variables
	local lc_type="$(eval echo "${LANG:-${LC_ALL:-$LC_CTYPE}}")"   # expand variables
	local home="$(eval echo "${workdir//\/root/\/tmp\/docker}")"   # expand variables
	local path="$(eval echo "$PATH")"                              # expand variables
	local message="$(eval echo "")"                                # expand variables
	local sysname="${SERVER_NAME:-${FULL_DOMAIN_NAME:-$HOSTNAME}}" # set hostname
	[ -f "$CONF_DIR/$SERVICE_NAME.exec_cmd.sh" ] && . "$CONF_DIR/$SERVICE_NAME.exec_cmd.sh"
	#
	if [ -z "$cmd" ]; then
		__post_execute 2>"/dev/stderr" | tee -p -a "/data/logs/init.txt"
		retVal=$?
		echo "Initializing $SCRIPT_NAME has completed"
		__script_exit $retVal
	else
		# ensure the command exists
		if [ ! -x "$cmd" ]; then
			echo "$name is not a valid executable"
			return 2
		fi
		# check and exit if already running
		if __proc_check "$name" || __proc_check "$cmd"; then
			return 0
		else
			# - - - - - - - - - - - - - - - - - - - - - - - - -
			# show message if env exists
			if [ -n "$cmd" ]; then
				[ -n "$SERVICE_USER" ] && echo "Setting up $cmd to run as $SERVICE_USER" || SERVICE_USER="root"
				[ -n "$SERVICE_PORT" ] && echo "$name will be running on port $SERVICE_PORT" || SERVICE_PORT=""
			fi
			if [ -n "$pre" ] && [ -n "$(command -v "$pre" 2>/dev/null)" ]; then
				export cmd_exec="$pre $cmd $args"
				message="Starting service: $name $args through $pre"
			else
				export cmd_exec="$cmd $args"
				message="Starting service: $name $args"
			fi
			[ -n "$su_exec" ] && echo "using $su_exec" | tee -a -p "/data/logs/init.txt"
			echo "$message" | tee -a -p "/data/logs/init.txt"
			su_cmd touch "$SERVICE_PID_FILE"
			if [ "$RESET_ENV" = "yes" ]; then
				env_command="$(echo "env -i HOME=\"$home\" LC_CTYPE=\"$lc_type\" PATH=\"$path\" HOSTNAME=\"$sysname\" USER=\"${SERVICE_USER:-$RUNAS_USER}\" $extra_env")"
				execute_command="$(__trim "$su_exec $env_command $cmd_exec")"
				if [ ! -f "$START_SCRIPT" ]; then
					cat <<EOF >"$START_SCRIPT"
#!/usr/bin/env bash
trap 'exitCode=\$?;[ \$exitCode -ne 0 ] && [ -f "\$SERVICE_PID_FILE" ] && rm -Rf "\$SERVICE_PID_FILE";exit \$exitCode' EXIT
#
set -Eeo pipefail
# Setting up $cmd to run as ${SERVICE_USER:-root} with env
retVal=10
cmd="$cmd"
args="$args"
SERVICE_NAME="$SERVICE_NAME"
SERVICE_PID_FILE="$SERVICE_PID_FILE"
LOG_DIR="$LOG_DIR"
execute_command="$execute_command"
\$execute_command 2>"/dev/stderr" >>"\$LOG_DIR/\$SERVICE_NAME.log" &
execPid=\$!
sleep 1
checkPID="\$(ps ax | awk '{print \$1}' | grep -v grep | grep "\$execPid$" || false)"
[ -n "\$execPid"  ] && [ -n "\$checkPID" ] && echo "\$execPid" >"\$SERVICE_PID_FILE" && retVal=0 || retVal=10
[ "\$retVal" = 0 ] && printf '%s\n' "\$SERVICE_NAME: \$execPid" >"/run/healthcheck/\$SERVICE_NAME" || echo "Failed to start $execute_command" >&2
exit \$retVal

EOF
				fi
			else
				if [ ! -f "$START_SCRIPT" ]; then
					execute_command="$(__trim "$su_exec $cmd_exec")"
					cat <<EOF >"$START_SCRIPT"
#!/usr/bin/env bash
trap 'exitCode=\$?;[ \$exitCode -ne 0 ] && [ -f "\$SERVICE_PID_FILE" ] && rm -Rf "\$SERVICE_PID_FILE";exit \$exitCode' EXIT
#
set -Eeo pipefail
# Setting up $cmd to run as ${SERVICE_USER:-root}
retVal=10
cmd="$cmd"
args="$args"
SERVICE_NAME="$SERVICE_NAME"
SERVICE_PID_FILE="$SERVICE_PID_FILE"
LOG_DIR="$LOG_DIR"
execute_command="$execute_command"
\$execute_command 2>>"/dev/stderr" >>"\$LOG_DIR/\$SERVICE_NAME.log" &
execPid=\$!
sleep 1
checkPID="\$(ps ax | awk '{print \$1}' | grep -v grep | grep "\$execPid$" || false)"
[ -n "\$execPid"  ] && [ -n "\$checkPID" ] && echo "\$execPid" >"\$SERVICE_PID_FILE" && retVal=0 || retVal=10
[ "\$retVal" = 0 ] || echo "Failed to start $execute_command" >&2
exit \$retVal

EOF
				fi
			fi
		fi
		[ -x "$START_SCRIPT" ] || chmod 755 -Rf "$START_SCRIPT"
		[ "$CONTAINER_INIT" = "yes" ] || eval sh -c "$START_SCRIPT"
		runExitCode=$?
	fi
	return $runExitCode
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
# username and password actions
__run_secure_function() {
	local filesperms
	if [ -n "$user_name" ] || [ -n "$user_pass" ]; then
		for filesperms in "${USER_FILE_PREFIX}"/*; do
			if [ -e "$filesperms" ]; then
				chmod -Rf 600 "$filesperms"
				chown -Rf $SERVICE_USER:$SERVICE_USER "$filesperms" 2>/dev/null
			fi
		done 2>/dev/null | tee -p -a "/data/logs/init.txt"
	fi
	if [ -n "$root_user_name" ] || [ -n "$root_user_pass" ]; then
		for filesperms in "${ROOT_FILE_PREFIX}"/*; do
			if [ -e "$filesperms" ]; then
				chmod -Rf 600 "$filesperms"
				chown -Rf $SERVICE_USER:$SERVICE_USER "$filesperms" 2>/dev/null
			fi
		done 2>/dev/null | tee -p -a "/data/logs/init.txt"
	fi
	unset filesperms
}
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Allow ENV_ variable - Import env file
__file_exists_with_content "/config/env/${SERVICE_NAME:-$SCRIPT_NAME}.sh" && . "/config/env/${SERVICE_NAME:-$SCRIPT_NAME}.sh"
__file_exists_with_content "/config/env/${SERVICE_NAME:-$SCRIPT_NAME}.local.sh" && . "/config/env/${SERVICE_NAME:-$SCRIPT_NAME}.local.sh"
# - - - - - - - - - - - - - - - - - - - - - - - - -
SERVICE_EXIT_CODE=0 # default exit code
# application specific
EXEC_CMD_NAME="$(basename -- "$EXEC_CMD_BIN")"                             # set the binary name
SERVICE_PID_FILE="/run/init.d/$EXEC_CMD_NAME.pid"                          # set the pid file location
SERVICE_PID_NUMBER="$(__pgrep "$EXEC_CMD_NAME")"                           # check if running
EXEC_CMD_BIN="$(type -P "$EXEC_CMD_BIN" || echo "$EXEC_CMD_BIN")"          # set full path
EXEC_PRE_SCRIPT="$(type -P "$EXEC_PRE_SCRIPT" || echo "$EXEC_PRE_SCRIPT")" # set full path
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Only run check
__check_service "$1" && SERVICE_IS_RUNNING=yes
# - - - - - - - - - - - - - - - - - - - - - - - - -
# ensure needed directories exists
[ -d "$LOG_DIR" ] || mkdir -p "$LOG_DIR"
[ -d "$RUN_DIR" ] || mkdir -p "$RUN_DIR"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# create auth directories
[ -n "$USER_FILE_PREFIX" ] && { [ -d "$USER_FILE_PREFIX" ] || mkdir -p "$USER_FILE_PREFIX"; }
[ -n "$ROOT_FILE_PREFIX" ] && { [ -d "$ROOT_FILE_PREFIX" ] || mkdir -p "$ROOT_FILE_PREFIX"; }
# - - - - - - - - - - - - - - - - - - - - - - - - -
[ -n "$RUNAS_USER" ] || RUNAS_USER="root"
[ -n "$SERVICE_USER" ] || SERVICE_USER="$RUNAS_USER"
[ -n "$SERVICE_GROUP" ] || SERVICE_GROUP="${SERVICE_USER:-$RUNAS_USER}"
[ "$IS_WEB_SERVER" = "yes" ] && RESET_ENV="yes" && __is_htdocs_mounted
[ "$IS_WEB_SERVER" = "yes" ] && [ -z "$SERVICE_PORT" ] && SERVICE_PORT="80"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Database env
if [ "$IS_DATABASE_SERVICE" = "yes" ] || [ "$USES_DATABASE_SERVICE" = "yes" ]; then
	RESET_ENV="no"
	DATABASE_CREATE="${ENV_DATABASE_CREATE:-$DATABASE_CREATE}"
	DATABASE_USER_NORMAL="${ENV_DATABASE_USER:-${DATABASE_USER_NORMAL:-$user_name}}"
	DATABASE_PASS_NORMAL="${ENV_DATABASE_PASSWORD:-${DATABASE_PASS_NORMAL:-$user_pass}}"
	DATABASE_USER_ROOT="${ENV_DATABASE_ROOT_USER:-${DATABASE_USER_ROOT:-$root_user_name}}"
	DATABASE_PASS_ROOT="${ENV_DATABASE_ROOT_PASSWORD:-${DATABASE_PASS_ROOT:-$root_user_pass}}"
	if [ -n "$DATABASE_PASS_NORMAL" ] && [ ! -f "${USER_FILE_PREFIX}/db_pass_user" ]; then
		echo "$DATABASE_PASS_NORMAL" >"${USER_FILE_PREFIX}/db_pass_user"
	fi
	if [ -n "$DATABASE_PASS_ROOT" ] && [ ! -f "${ROOT_FILE_PREFIX}/db_pass_root" ]; then
		echo "$DATABASE_PASS_ROOT" >"${ROOT_FILE_PREFIX}/db_pass_root"
	fi
fi
# - - - - - - - - - - - - - - - - - - - - - - - - -
# [DATABASE_DIR_[SQLITE,REDIS,POSTGRES,MARIADB,COUCHDB,MONGODB,SUPABASE]]
if [ "$DATABASE_SERVICE_TYPE" = "custom" ]; then
	DATABASE_DIR="${DATABASE_DIR_CUSTOM:-/data/db/custom}"
	DATABASE_BASE_DIR="${DATABASE_DIR_CUSTOM:-/data/db/custom}"
	DATABASE_ADMIN_WWW_ROOT="${DATABASE_ADMIN_WWW_ROOT_CUSTOM:-/usr/local/share/httpd/admin/databases}"
	[ -d "$DATABASE_ADMIN_WWW_ROOT" ] && SERVER_ADMIN_URL="${SERVER_ADMIN_URL_CUSTOM:-/admin/dbadmin}"
elif [ "$SERVICE_NAME" = "redis" ] || [ "$DATABASE_SERVICE_TYPE" = "redis" ]; then
	DATABASE_DIR="${DATABASE_DIR_REDIS:-/data/db/redis}"
	DATABASE_BASE_DIR="${DATABASE_DIR_REDIS:-/data/db/redis}"
	DATABASE_ADMIN_WWW_ROOT="${DATABASE_ADMIN_WWW_ROOT_REDIS:-/usr/local/share/httpd/admin/redis}"
	[ -d "$DATABASE_ADMIN_WWW_ROOT" ] && SERVER_ADMIN_URL="${SERVER_ADMIN_URL_REDIS:-/admin/redis}"
elif [ "$SERVICE_NAME" = "postgres" ] || [ "$DATABASE_SERVICE_TYPE" = "postgres" ]; then
	DATABASE_DIR="${DATABASE_DIR_POSTGRES:-/data/db/postgres}"
	DATABASE_BASE_DIR="${DATABASE_DIR_POSTGRES:-/data/db/postgres}"
	DATABASE_ADMIN_WWW_ROOT="${DATABASE_ADMIN_WWW_ROOT_POSTGRES:-/usr/local/share/httpd/admin/postgres}"
	[ -d "$DATABASE_ADMIN_WWW_ROOT" ] && SERVER_ADMIN_URL="${SERVER_ADMIN_URL_POSTGRES:-/admin/postgres}"
elif [ "$SERVICE_NAME" = "mariadb" ] || [ "$DATABASE_SERVICE_TYPE" = "mariadb" ]; then
	DATABASE_DIR="${DATABASE_DIR_MARIADB:-/data/db/mariadb}"
	DATABASE_BASE_DIR="${DATABASE_DIR_MARIADB:-/data/db/mariadb}"
	DATABASE_ADMIN_WWW_ROOT="${DATABASE_ADMIN_WWW_ROOT_MARIADB:-/usr/local/share/httpd/admin/mysql}"
	[ -d "$DATABASE_ADMIN_WWW_ROOT" ] && SERVER_ADMIN_URL="${SERVER_ADMIN_URL_MARIADB:-/admin/mysql}"
elif [ "$SERVICE_NAME" = "mysql" ] || [ "$DATABASE_SERVICE_TYPE" = "mysql" ]; then
	DATABASE_DIR="${DATABASE_DIR_MYSQL:-/data/db/mysql}"
	DATABASE_BASE_DIR="${DATABASE_DIR_MYSQL:-/data/db/mysql}"
	DATABASE_ADMIN_WWW_ROOT="${DATABASE_ADMIN_WWW_ROOT_MYSQL:-/usr/local/share/httpd/admin/mysql}"
	[ -d "$DATABASE_ADMIN_WWW_ROOT" ] && SERVER_ADMIN_URL="${SERVER_ADMIN_URL_MYSQL:-/admin/mysql}"
elif [ "$SERVICE_NAME" = "couchdb" ] || [ "$DATABASE_SERVICE_TYPE" = "couchdb" ]; then
	DATABASE_DIR="${DATABASE_DIR_COUCHDB:-/data/db/couchdb}"
	DATABASE_BASE_DIR="${DATABASE_DIR_COUCHDB:-/data/db/couchdb}"
	DATABASE_ADMIN_WWW_ROOT="${DATABASE_ADMIN_WWW_ROOT_COUCHDB:-/usr/local/share/httpd/admin/couchdb}"
	[ -d "$DATABASE_ADMIN_WWW_ROOT" ] && SERVER_ADMIN_URL="${SERVER_ADMIN_URL_COUCHDB:-/admin/couchdb}"
elif [ "$SERVICE_NAME" = "mongodb" ] || [ "$DATABASE_SERVICE_TYPE" = "mongodb" ]; then
	DATABASE_DIR="${DATABASE_DIR_MONGODB:-/data/db/mongodb}"
	DATABASE_BASE_DIR="${DATABASE_DIR_MONGODB:-/data/db/mongodb}"
	DATABASE_ADMIN_WWW_ROOT="${DATABASE_ADMIN_WWW_ROOT_MONGODB:-/usr/local/share/httpd/admin/mongodb}"
	[ -d "$DATABASE_ADMIN_WWW_ROOT" ] && SERVER_ADMIN_URL="${SERVER_ADMIN_URL_MONGODB:-/admin/mongodb}"
elif [ "$SERVICE_NAME" = "supabase" ] || [ "$DATABASE_SERVICE_TYPE" = "supabase" ]; then
	DATABASE_DIR="${DATABASE_DIR_SUPABASE:-/data/db/supabase}"
	DATABASE_BASE_DIR="${DATABASE_DIR_SUPABASE:-/data/db/supabase}"
	DATABASE_ADMIN_WWW_ROOT="${DATABASE_ADMIN_WWW_ROOT_SUPABASE:-/usr/local/share/httpd/admin/supabase}"
	[ -d "$DATABASE_ADMIN_WWW_ROOT" ] && SERVER_ADMIN_URL="${SERVER_ADMIN_URL_SUPBASE:-/admin/supabase}"
elif [ "$SERVICE_NAME" = "sqlite" ] || [ "$DATABASE_SERVICE_TYPE" = "sqlite" ]; then
	DATABASE_DIR="${DATABASE_DIR_SQLITE:-/data/db/sqlite}/$SERVER_NAME"
	DATABASE_BASE_DIR="${DATABASE_DIR_SQLITE:-/data/db/sqlite}/$SERVER_NAME"
	DATABASE_ADMIN_WWW_ROOT="${DATABASE_ADMIN_WWW_ROOT_SQLITE:-/usr/local/share/httpd/admin/sqlite}"
	[ -d "$DATABASE_ADMIN_WWW_ROOT" ] && SERVER_ADMIN_URL="${SERVER_ADMIN_URL_SQLITE:-/admin/sqlite}"
	[ -d "$DATABASE_DIR" ] || mkdir -p "$DATABASE_DIR"
	chmod 777 "$DATABASE_DIR"
fi
[ -n "$DATABASE_ADMIN_WWW_ROOT" ] && { [ ! -d "$DATABASE_ADMIN_WWW_ROOT" ] || mkdir -p "${DATABASE_ADMIN_WWW_ROOT}"; }
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Allow variables via imports - Overwrite existing
[ -f "/config/env/${SERVICE_NAME:-$SCRIPT_NAME}.sh" ] && . "/config/env/${SERVICE_NAME:-$SCRIPT_NAME}.sh"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# set password to random if variable is random
[ "$user_pass" = "random" ] && user_pass="$(__random_password ${RANDOM_PASS_USER:-16})"
# - - - - - - - - - - - - - - - - - - - - - - - - -
[ "$root_user_pass" = "random" ] && root_user_pass="$(__random_password ${RANDOM_PASS_ROOT:-16})"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Allow setting initial users and passwords via environment and save to file
[ -n "$user_name" ] && echo "$user_name" >"${USER_FILE_PREFIX}/${SERVICE_NAME}_name"
[ -n "$user_pass" ] && echo "$user_pass" >"${USER_FILE_PREFIX}/${SERVICE_NAME}_pass"
[ -n "$root_user_name" ] && echo "$root_user_name" >"${ROOT_FILE_PREFIX}/${SERVICE_NAME}_name"
[ -n "$root_user_pass" ] && echo "$root_user_pass" >"${ROOT_FILE_PREFIX}/${SERVICE_NAME}_pass"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# create needed dirs
[ -d "$LOG_DIR" ] || mkdir -p "$LOG_DIR"
[ -d "$RUN_DIR" ] || mkdir -p "$RUN_DIR"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Allow per init script usernames and passwords
__file_exists_with_content "${USER_FILE_PREFIX}/${SERVICE_NAME}_name" && user_name="$(<"${USER_FILE_PREFIX}/${SERVICE_NAME}_name")"
__file_exists_with_content "${USER_FILE_PREFIX}/${SERVICE_NAME}_pass" && user_pass="$(<"${USER_FILE_PREFIX}/${SERVICE_NAME}_pass")"
__file_exists_with_content "${ROOT_FILE_PREFIX}/${SERVICE_NAME}_name" && root_user_name="$(<"${ROOT_FILE_PREFIX}/${SERVICE_NAME}_name")"
__file_exists_with_content "${ROOT_FILE_PREFIX}/${SERVICE_NAME}_pass" && root_user_pass="$(<"${ROOT_FILE_PREFIX}/${SERVICE_NAME}_pass")"
__file_exists_with_content "${USER_FILE_PREFIX}/db_pass_user" && DATABASE_PASS_NORMAL="$(<"${USER_FILE_PREFIX}/db_pass_user")"
__file_exists_with_content "${ROOT_FILE_PREFIX}/db_pass_root" && DATABASE_PASS_ROOT="$(<"${ROOT_FILE_PREFIX}/db_pass_root")"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# set hostname for script
sysname="${SERVER_NAME:-${FULL_DOMAIN_NAME:-$HOSTNAME}}"
# - - - - - - - - - - - - - - - - - - - - - - - - -
__create_service_env
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Setup /config directories
__init_config_etc
# - - - - - - - - - - - - - - - - - - - - - - - - -
# pre-run function
__execute_prerun
# - - - - - - - - - - - - - - - - - - - - - - - - -
# create user if needed
__create_service_user "$SERVICE_USER" "$SERVICE_GROUP" "${WORK_DIR:-/home/$SERVICE_USER}" "${SERVICE_UID:-}" "${SERVICE_GID:-}"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Modify user if needed
__set_user_group_id $SERVICE_USER ${SERVICE_UID:-} ${SERVICE_GID:-}
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Create base directories
__setup_directories
# - - - - - - - - - - - - - - - - - - - - - - - - -
# set switch user command
__switch_to_user
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Initialize the home/working dir
__init_working_dir
# - - - - - - - - - - - - - - - - - - - - - - - - -
# show init message
__pre_message
# - - - - - - - - - - - - - - - - - - - - - - - - -
#
__initialize_db_users
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Initialize ssl
__update_ssl_conf
__update_ssl_certs
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Set permissions in ${USER_FILE_PREFIX} and ${ROOT_FILE_PREFIX}
__run_secure_function
# - - - - - - - - - - - - - - - - - - - - - - - - -
__run_precopy
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Copy /config to /etc
for config_2_etc in $CONF_DIR $ADDITIONAL_CONFIG_DIRS; do
	__initialize_system_etc "$config_2_etc" 2>/dev/stderr | tee -p -a "/data/logs/init.txt"
done
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Replace variables
__initialize_replace_variables "$ETC_DIR" "$CONF_DIR" "$ADDITIONAL_CONFIG_DIRS" "$WWW_ROOT_DIR"
# - - - - - - - - - - - - - - - - - - - - - - - - -
#
__initialize_database
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Updating config files
__update_conf_files
# - - - - - - - - - - - - - - - - - - - - - - - - -
# run the pre execute commands
__pre_execute
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Set permissions
__fix_permissions "$SERVICE_USER" "$SERVICE_GROUP"
# - - - - - - - - - - - - - - - - - - - - - - - - -
#
__run_pre_execute_checks 2>/dev/stderr | tee -a -p "/data/logs/entrypoint.log" "/data/logs/init.txt" || return 20
# - - - - - - - - - - - - - - - - - - - - - - - - -
__run_start_script 2>>/dev/stderr | tee -p -a "/data/logs/entrypoint.log"
errorCode=$?
if [ -n "$EXEC_CMD_BIN" ]; then
	if [ "$errorCode" -eq 0 ]; then
		SERVICE_EXIT_CODE=0
		SERVICE_IS_RUNNING="yes"
	else
		SERVICE_EXIT_CODE=$errorCode
		SERVICE_IS_RUNNING="${SERVICE_IS_RUNNING:-no}"
		[ -s "$SERVICE_PID_FILE" ] || rm -Rf "$SERVICE_PID_FILE"
	fi
	SERVICE_EXIT_CODE=0
fi
# - - - - - - - - - - - - - - - - - - - - - - - - -
# start the post execute function in background
__post_execute 2>"/dev/stderr" | tee -p -a "/data/logs/init.txt" &
# - - - - - - - - - - - - - - - - - - - - - - - - -
__script_exit $SERVICE_EXIT_CODE
