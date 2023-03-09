#!/usr/bin/env bash
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
export PATH="/usr/local/etc/docker/bin:/usr/local/bin:/usr/bin:/usr/sbin:/bin:/sbin"
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# run trap command on exit
trap -- 'retVal=$?;[ "$SERVICE_IS_RUNNING" != "true" ] && [ -f "/run/$EXEC_CMD_BIN.init.pid" ] && rm -Rf "/run/$EXEC_CMD_BIN.init.pid";exit $retVal' SIGINT SIGTERM EXIT
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html
[ "$DEBUGGER" = "on" ] && echo "Enabling debugging" && set -o pipefail -x$DEBUGGER_OPTIONS || set -o pipefail
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
# execute command variables
WORKDIR=""                               # change to directory
ALT_SCRIPT="no"                          # Set to yes to run the __alt_execute_script
SERVICE_USER="root"                      # execute command as another user
SERVICE_UID="0"                          # set the user id
SERVICE_PORT="${PORT:-80}"               # port which service is listening on
EXEC_CMD_BIN="nginx"                     # command to execute
EXEC_CMD_ARGS="-c /etc/nginx/nginx.conf" # command arguments
PRE_EXEC_MESSAGE=""                      # Show message before execute
SERVICE_EXIT_CODE=0                      # default exit code
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Other variables that are needed

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# use this function to update config files - IE: change port
__update_conf_files() {
  local etc_dir="/etc/nginx"
  local conf_dir="/config/nginx"
  local www_dir="${WWW_ROOT_DIR:-/data/htdocs}"
  #
  nginx_bin="$(type -P 'nginx')"
  [ -e "$conf_dir" ] && [ -n "$nginx_bin" ] || return 0
  echo "Initializing nginx web server in $conf_dir"
  [ -d "$etc_dir" ] || mkdir -p "$etc_dir"
  [ -d "$conf_dir" ] && cp -Rf "$conf_dir/." "$etc_dir/"
  if [ "$SSL_ENABLED" = "true" ]; then
    __file_copy "$conf_dir/nginx.ssl.conf" "$etc_dir/nginx.ssl.conf"
  else
    [ -n "$ssl_conf" ] && [ -f "$ssl_conf" ] && rm -Rf "$etc_dir/nginx.ssl.conf"
  fi
  __replace "SERVER_PORT" "${SERVICE_PORT:-80}" "$etc_dir/nginx.conf"
  __replace "SERVER_PORT" "${SERVICE_PORT:-80}" "$etc_dir/vhosts.d/nginx.conf"
  [ -f "$www_dir/www/index.php" ] && __replace "SERVER_SOFTWARE" "nginx" "$www_dir/www/index.php"
  [ -f "$www_dir/www/index.html" ] && __replace "SERVER_SOFTWARE" "nginx" "$www_dir/www/index.html"
  if [ -z "$PHP_BIN_DIR" ]; then
    [ -f "$www_dir/www/info.php" ] && echo "PHP support is not enabled" >"$www_dir/www/info.php"
    [ -f "$etc_dir/conf.d/php-fpm.conf" ] && echo "# PHP support is not enabled" >"$etc_dir/conf.d/php-fpm.conf"
  fi
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

  return 0
}
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Custom functions

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# alternate script to start server
__alt_execute_script() { true; }
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# process check functions
__pcheck() { [ -n "$(type -P pgrep 2>/dev/null)" ] && pgrep -x "$1" &>/dev/null && return 0 || return 10; }
__pgrep() { __pcheck "${1:-EXEC_CMD_BIN}" || __ps aux 2>/dev/null | grep -Fw " ${1:-$EXEC_CMD_BIN}" | grep -qv ' grep' | grep '^' && return 0 || return 10; }
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# Allow ENV_ variable
[ -f "/config/env/$EXEC_CMD_BIN.sh" ] && "/config/env/$EXEC_CMD_BIN.sh" # Import env file
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
WORKDIR="${ENV_WORKDIR:-$WORKDIR}"                            # change to directory
ALT_SCRIPT="${ENV_ALT_SCRIPT:-$ALT_SCRIPT}"                   # Set to yes to run the __alt_execute_script
SERVICE_USER="${ENV_SERVICE_USER:-$SERVICE_USER}"             # execute command as another user
SERVICE_UID="${ENV_SERVICE_UID:-$SERVICE_UID}"                # set the user id
SERVICE_PORT="${ENV_SERVICE_PORT:-$SERVICE_PORT}"             # port which service is listening on
EXEC_CMD_BIN="${ENV_EXEC_CMD_BIN:-$EXEC_CMD_BIN}"             # command to execute
EXEC_CMD_ARGS="${ENV_EXEC_CMD_ARGS:-$EXEC_CMD_ARGS}"          # command arguments
PRE_EXEC_MESSAGE="${ENV_PRE_EXEC_MESSAGE:-$PRE_EXEC_MESSAGE}" # Show message before execute
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
__update_ssl_certs
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
# run the pre execute commands
[ -n "$PRE_EXEC_MESSAGE" ] && echo "$PRE_EXEC_MESSAGE"
__pre_execute
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
WORKDIR="${WORKDIR:-}"
if [ "$SERVICE_USER" = "root" ] || [ -z "$SERVICE_USER" ]; then
  su_needed="false"
  su_cmd_bin="eval"
  su_cmd() { eval "$@" || return 1; }
elif [ "$(builtin type -P gosu)" ]; then
  su_cmd_bin="gosu $SERVICE_USER"
  su_cmd() { gosu $SERVICE_USER "$@" || return 1; }
elif [ "$(builtin type -P runuser)" ]; then
  su_cmd_bin="runuser -u $SERVICE_USER"
  su_cmd() { runuser -u $SERVICE_USER "$@" || return 1; }
elif [ "$(builtin type -P sudo)" ]; then
  su_cmd_bin="sudo -u $SERVICE_USER"
  su_cmd() { sudo -u $SERVICE_USER "$@" || return 1; }
elif [ "$(builtin type -P su)" ]; then
  su_cmd_bin="su -s /bin/sh - $SERVICE_USER"
  su_cmd() { su -s /bin/sh - $SERVICE_USER -c "$@" || return 1; }
else
  echo "Can not switch to $SERVICE_USER"
  exit 10
fi
if [ -n "$WORKDIR" ] && [ -n "$SERVICE_USER" ]; then
  echo "Fixing file permissions"
  su_cmd chown -Rf $SERVICE_USER $WORKDIR
fi
if [ "$su_needed" = "false" ]; then
  echo "Starting service: $EXEC_CMD_BIN $EXEC_CMD_ARGS"
else
  echo "Starting service: $EXEC_CMD_BIN $EXEC_CMD_ARGS as $SERVICE_USER"
fi
export SERVICE_IS_RUNNING="true"
su_cmd "touch /run/$EXEC_CMD_BIN.init.pid"
if [ "$ALT_SCRIPT" = "yes" ]; then
  __alt_execute_script "$@"
else
  su_cmd "$EXEC_CMD_BIN $EXEC_CMD_ARGS" || echo "Failed to execute: $EXEC_CMD_BIN $EXEC_CMD_ARGS"
fi
[ "$?" -ne 0 ] && SERVICE_IS_RUNNING="false" && SERVICE_EXIT_CODE=10 && rm -Rf "/run/$EXEC_CMD_BIN.init.pid"
# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
exit $SERVICE_EXIT_CODE
