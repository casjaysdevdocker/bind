#!/usr/bin/env bash
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html
[ "$DEBUGGER" = "on" ] && echo "Enabling debugging" && set -o pipefail -x$DEBUGGER_OPTIONS || set -o pipefail
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
export PATH="/usr/local/etc/docker/bin:/usr/local/bin:/usr/bin:/usr/sbin:/bin:/sbin"
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# run trap command on exit
trap 'retVal=$?;[ "$SERVICE_IS_RUNNING" != "true" ] && [ -f "/run/init.d/$EXEC_CMD_BIN.pid" ] && rm -Rf "/run/init.d/$EXEC_CMD_BIN.pid";exit $retVal' SIGINT SIGTERM EXIT
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# import the functions file
if [ -f "/usr/local/etc/docker/functions/entrypoint.sh" ]; then
  . "/usr/local/etc/docker/functions/entrypoint.sh"
fi
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# import variables
for set_env in "/root/env.sh" "/usr/local/etc/docker/env"/*.sh "/config/env"/*.sh; do
  [ -f "$set_env" ] && . "$set_env"
done
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Custom functions
__rndc_key() { grep -s 'key "rndc-key" ' /etc/named.conf | grep -v 'KEY_RNDC' | sed 's|.*secret ||g;s|"||g;s|;.*||g' | grep '^' || return; }
__tsig_key() { tsig-keygen -a hmac-sha256 | grep 'secret' | sed 's|.*secret "||g;s|"||g;s|;||g' | grep '^' || echo 'wp/HApbthaVPjwqgp6ziLlmnkyLSNbRTehkdARBDcpI='; }
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# execute command variables
WORKDIR=""                                  # set working directory
SERVICE_UID="0"                             # set the user id
SERVICE_USER="root"                         # execute command as another user
SERVICE_PORT="53"                           # port which service is listening on
EXEC_CMD_BIN="named"                        # command to execute
EXEC_CMD_ARGS="-g -c /etc/named/named.conf" # command arguments
PRE_EXEC_MESSAGE=""                         # Show message before execute
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Other variables that are needed
etc_dir="/etc/named"
var_dir="/var/named"
conf_dir="/config/named"
data_dir="/data/named"
KEY_RNDC="${KEY_RNDC:-$(__tsig_key)}"
KEY_DHCP="${KEY_DHCP:-$(__tsig_key)}"
KEY_BACKUP="${KEY_BACKUP:-$(__tsig_key)}"
KEY_CERTBOT="${KEY_CERTBOT:-$(__tsig_key)}"
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# use this function to update config files - IE: change port
__update_conf_files() {
  mkdir -p "$conf_dir/keys" "$data_dir/zones" "/tmp/named" "/run/named" "/data/log/named"
  [ -f "/config/named/named.conf" ] || cp -Rf "/etc/named/." "/config/named/"
  sed -i 's|REPLACE_HOSTNAME|'$HOSTNAME'|g' "$etc_dir"/named.conf              #&>/dev/null
  sed -i 's|REPLACE_KEY_DHCP|'$KEY_DHCP'|g' "$etc_dir"/named.conf              #&>/dev/null
  sed -i 's|REPLACE_KEY_BACKUP|'$KEY_BACKUP'|g' "$etc_dir"/named.conf          #&>/dev/null
  sed -i 's|REPLACE_KEY_CERTBOT|'$KEY_CERTBOT'|g' "$etc_dir"/named.conf        #&>/dev/null
  sed -i 's|REPLACE_KEY_RNDC|'$KEY_RNDC'|g' "$etc_dir"/named.conf              #&>/dev/null
  sed -i 's|REPLACE_KEY_RNDC|'$KEY_RNDC'|g' "$etc_dir"/rndc.key                #&>/dev/null
  sed -i 's|REPLACE_KEY_CERTBOT|'$KEY_CERTBOT'|g' $etc_dir/certbot-update.conf #&>/dev/null
  #
  if [ ! -f "/var/named/zones/$HOSTNAME.zone" ]; then
    cat <<EOF | tee "/var/named/zones/$HOSTNAME.zone" &>/dev/null
; config for $HOSTNAME
@                         IN  SOA     $HOSTNAME. root.$HOSTNAME. ( $(date +'%Y%m%d%S') 10800 3600 1209600 38400)
                          IN  NS      $HOSTNAME.
$HOSTNAME.                IN  A       $CONTAINER_IP4_ADDRESS

EOF
  fi
  #
  for dns_file in "$data_dir/zones"/*; do
    file_name="$(basename "$dns_file")"
    domain_name="$(grep -Rs '\$ORIGIN' "$dns_file" | awk '{print $NF}' | sed 's|.$||g')"
    if [ -f "$dns_file" ]; then
      cp -Rf "$dns_file" "$var_dir/zones/$file_name"
      if ! grep -qs "$domain_name" "$etc_dir/named.conf" && [ -n "$domain_name" ]; then
        cat <<EOF
  #  ********** begin $domain_name **********
  zone "$domain_name" {
        type master;
        file "$var_dir/zones/$file_name";
        notify yes;
        allow-update {key "certbot."; key "dhcp-key"; trusted;};
        allow-transfer { any; key "backup-key"; };
    };
#  ********** end $domain_name **********

EOF
      fi
    fi
  done

  return 0
}
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# use this function to setup ssl support
__update_ssl_conf() {

  return 0
}
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# function to run before executing
__pre_execute() {
  [ -n "$PRE_EXEC_MESSAGE" ] && echo "$PRE_EXEC_MESSAGE"
  chown -Rf named:named "$etc_dir" "$var_dir" "/run/named" "/tmp/named" && echo "changed ownership to named"
  chmod -f 777 "/etc/named" "/etc/named/keys" "/var/named/zones"
  chmod -f 777 "/var/named" "/tmp/named" "/data/log/named" && echo "changed folder permissions to 777"
  sleep 2

  return 0
}
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# script to start server
__run_start_script() {
  case "$1" in
  check) shift 1 && __pgrep $EXEC_CMD_BIN || return 5 ;;
  *)
    su_cmd $EXEC_CMD_BIN $EXEC_CMD_ARGS &>>/data/log/named/debug.log &
    sleep 10 && tail -f /data/log/named/* || return 10
    ;;
  esac
}
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# process check functions
__pcheck() { [ -n "$(type -P pgrep 2>/dev/null)" ] && pgrep -x "$1" &>/dev/null && return 0 || return 10; }
__pgrep() { __pcheck "${1:-EXEC_CMD_BIN}" || __ps aux 2>/dev/null | grep -Fw " ${1:-$EXEC_CMD_BIN}" | grep -qv ' grep' | grep '^' && return 0 || return 10; }
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Allow ENV_ variable
[ -f "/config/env/$EXEC_CMD_BIN.sh" ] && "/config/env/$EXEC_CMD_BIN.sh" # Import env file
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
WORKDIR="${ENV_WORKDIR:-$WORKDIR}"                            # change to directory
SERVICE_USER="${ENV_SERVICE_USER:-$SERVICE_USER}"             # execute command as another user
SERVICE_UID="${ENV_SERVICE_UID:-$SERVICE_UID}"                # set the user id
SERVICE_PORT="${ENV_SERVICE_PORT:-$SERVICE_PORT}"             # port which service is listening on
EXEC_CMD_BIN="${ENV_EXEC_CMD_BIN:-$EXEC_CMD_BIN}"             # command to execute
EXEC_CMD_ARGS="${ENV_EXEC_CMD_ARGS:-$EXEC_CMD_ARGS}"          # command arguments
PRE_EXEC_MESSAGE="${ENV_PRE_EXEC_MESSAGE:-$PRE_EXEC_MESSAGE}" # Show message before execute
SERVICE_EXIT_CODE=0                                           # default exit code
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
printf '%s\n' "# - - - Attempting to start $EXEC_CMD_BIN - - - #"
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# ensure the command exists
if [ ! -f "$(type -P "$EXEC_CMD_BIN")" ] && [ -z "$EXEC_CMD_BIN" ]; then
  echo "$EXEC_CMD_BIN is not a valid command"
  exit 2
fi
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# check if process is already running
if __pgrep "$EXEC_CMD_BIN"; then
  SERVICE_IS_RUNNING="true"
  echo "$EXEC_CMD_BIN is running"
  exit 0
fi
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# show message if env exists
if [ -n "$EXEC_CMD_BIN" ]; then
  [ -n "$SERVICE_USER" ] && echo "Setting up service to run as $SERVICE_USER"
  [ -n "$SERVICE_PORT" ] && echo "$EXEC_CMD_BIN will be running on $SERVICE_PORT"
fi
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Change to working directory
[ -n "$WORKDIR" ] && mkdir -p "$WORKDIR" && __cd "$WORKDIR" && echo "Changed to $PWD"
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Updating config files
__update_conf_files
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Initialize ssl
__update_ssl_conf
__update_ssl_certs
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# run the pre execute commands
[ -n "$PRE_EXEC_MESSAGE" ] && echo "$PRE_EXEC_MESSAGE"
__pre_execute
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
WORKDIR="${WORKDIR:-}"
if [ "$SERVICE_USER" = "root" ] || [ -z "$SERVICE_USER" ]; then
  su_cmd_bin=""
  su_cmd() { eval $su_cmd_bin "$@" || return 1; }
elif [ "$(builtin type -P gosu)" ]; then
  su_cmd_bin="gosu $SERVICE_USER"
  su_cmd() { eval $su_cmd_bin "$@" || return 1; }
elif [ "$(builtin type -P runuser)" ]; then
  su_cmd_bin="runuser -u $SERVICE_USER"
  su_cmd() { eval $su_cmd_bin "$@" || return 1; }
elif [ "$(builtin type -P sudo)" ]; then
  su_cmd_bin="sudo -u $SERVICE_USER"
  su_cmd() { eval $su_cmd_bin "$@" || return 1; }
elif [ "$(builtin type -P su)" ]; then
  su_cmd_bin="su -s /bin/sh - $SERVICE_USER"
  su_cmd() { eval $su_cmd_bin -c "$@" || return 1; }
else
  echo "Can not switch to $SERVICE_USER"
  exit 10
fi
if [ -n "$WORKDIR" ] && [ -n "$SERVICE_USER" ]; then
  echo "Fixing file permissions"
  su_cmd chown -Rf $SERVICE_USER $WORKDIR
fi
if __pgrep $EXEC_CMD_BIN && [ -f "/run/init.d/$EXEC_CMD_BIN.pid" ]; then
  SERVICE_EXIT_CODE=1
  echo "$EXEC_CMD_BIN" is already running
else
  echo "Starting service: $EXEC_CMD_BIN $EXEC_CMD_ARGS"
  su_cmd touch /run/init.d/$EXEC_CMD_BIN.pid
  __run_start_script "$@" |& tee -a "/tmp/entrypoint.log" || echo "Failed to execute: $EXEC_CMD_BIN $EXEC_CMD_ARGS"
  [ "$?" -ne 0 ] && SERVICE_IS_RUNNING="false" && SERVICE_EXIT_CODE=10 && rm -Rf "/run/init.d/$EXEC_CMD_BIN.pid"
fi
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
exit $SERVICE_EXIT_CODE
