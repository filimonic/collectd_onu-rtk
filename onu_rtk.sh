#!/bin/ash
# Script to use with collectd exec plugin to get information from some Realtek GPON\
# EPON\XPON ONU\ONT via telnet

# Copyright (C) 2025 Alexey D. Filimonov
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.

# Version: 1.0.1
# Author: Alexey D. Filimonov <alexey@filimonic.net>
# Project page: https://github.com/filimonic/collectd-exec_onu_rtk

# Approximate interval can be passed as argument#1 in seconds, defaults 60
# Startup delay can be passed as argument#2 in seconds, defaults COLLECTD_INTERVAL
# Env variables:
# DEBUG_CMD=[0|1]. Prints debug to output. For interactive debuging
# DEBUG_OUTPUT_FILE=[path]. Duplicates output to this file

LOOP_INTERVAL=${1:-60}
#DEBUG_OUTPUT_FILE=/tmp/onu_rtk.log
#DEBUG_CMD=1
DEBUG_OUTPUT_FILE=${DEBUG_OUTPUT_FILE:-/dev/null}

PLUGIN_NAME="onu_rtk"
UCI_CONFIG_NAME="collectd-${PLUGIN_NAME}"
SEXPECT_BIN="$(which sexpect)"
TELNET_BIN="$(which telnet)"
TELNET_CMD="${TELNET_BIN} -c -E"
SEVERITY_FAILURE="failure"
SEVERITY_WARNING="warning"
SEVERITY_OK="okay"
STARTUP_DELAY="${2:-${COLLECTD_INTERVAL:-$LOOP_INTERVAL}}"
STARTUP_DELAY=${STARTUP_DELAY%%.*} # remove decimals

# Include OpenWRT functions
. /lib/functions.sh

DEBUG_CMD_FLAGS=""
if [ -n "${DEBUG_CMD}" ] && [ "${DEBUG_CMD}" -ne 0 ]; then
  set -x
  DEBUG_CMD_FLAGS=" -debug "
fi
CMD_SPAWN="${SEXPECT_BIN} spawn -term xterm "
CMD_EXPECT="${SEXPECT_BIN} ${DEBUG_CMD_FLAGS} expect "
CMD_SEND="${SEXPECT_BIN} ${DEBUG_CMD_FLAGS} send "
CMD_GET_IDX="${SEXPECT_BIN} ${DEBUG_CMD_FLAGS} expect_out -index "
CMD_WAIT_EXIT="${SEXPECT_BIN} ${DEBUG_CMD_FLAGS} wait "

enter_cli() {
  $CMD_SPAWN -idle-close $(expr "${LOOP_INTERVAL}" '*' '2') -ttl $(expr "${LOOP_INTERVAL}" '/' '2') ${TELNET_CMD} ${ONU_SERVER} || return 11
  $CMD_EXPECT -timeout 5 -re '.*\nUsername:' >/dev/null || return 12
  $CMD_SEND -enter -env ONU_USERNAME >/dev/null || return 13
  $CMD_EXPECT -timeout 5 -re '.*\nPassword:' >/dev/null || return 14
  $CMD_SEND -enter -env ONU_PASSWORD >/dev/null || return 15
  $CMD_EXPECT -timeout 5 -re '.*\n#\s' >/dev/null || return 16
}

enter_diag() {
  $CMD_SEND -enter 'diag' >/dev/null || return 21
  $CMD_EXPECT -timeout 5 -re '.*\n\S+\.\d>\s' >/dev/null || return 22
}

exit_diag() {
  $CMD_SEND -enter 'exit' >/dev/null || return 31
  $CMD_EXPECT -timeout 5 -re '.*\n\S+\.\d>\s' >/dev/null || return 32
}

exit_cli() {
  $CMD_SEND -enter ' exit' >/dev/null || return 41
  $CMD_WAIT_EXIT >/dev/null || return 0
}

report_notification() {
  local SEVERITY=$1
  shift
  echo -e "PUTNOTIF severity=${SEVERITY} time=${EPOCHSECONDS} message=$@" |
    tee -a "${DEBUG_OUTPUT_FILE}"
}

report_value() {
  local KIND=$1 COMMAND="$2" REGEX="$3" CAPTURE_GROUP_INDEX="$4" \
    INSTANCE_NAME="$5" SUBSYSTEM="$6" TYPE="$7" RET_CODE REGEX_FULL VALUE VALUE_TIME
  if [ "$KIND" == "diag" ]; then
    REGEX_FULL="${REGEX}.*\n\S+\.\d>\s"
  elif [ "$KIND" == "cli" ]; then
    REGEX_FULL="${REGEX}.*\n#\s"
  else
    report_notification $SEVERITY_FAILURE \
      "Unexpected KIND='${KIND}' passed to ${FUNCNAME}"
    return 0
  fi
  $CMD_SEND -enter "$CMD" >/dev/null || return 51
  $CMD_EXPECT -timeout 5 -re "$REGEX_FULL" >/dev/null || return 52
  RET_CODE=$?
  VALUE_TIME=$EPOCHSECONDS
  if [ "${RET_CODE}" -ne 0 ]; then
    report_notification $SEVERITY_FAILURE "Failed getting result with " \
      "COMMAND='${COMMAND}' and REGEX_FULL='${REGEX_FULL}' for INSTANCE_NAME='${INSTANCE_NAME}': " \
      "exit code ${RET_CODE}"
    return 0
  fi
  VALUE=$($CMD_GET_IDX $CAPTURE_GROUP_INDEX)
  RET_CODE=$?
  if [ "${RET_CODE}" -ne 0 ]; then
    report_notification $SEVERITY_FAILURE "Failed getting capture group " \
      "${CAPTURE_GROUP_INDEX} for COMMAND='${CMD_GET_IDX} ${CAPTURE_GROUP_INDEX}' " \
      "and REGEX_FULL='${REGEX_FULL}' for INSTANCE_NAME='${INSTANCE_NAME}': exit code ${RET_CODE}"
    return 0
  fi
  
  ECHO_TEXT="PUTVAL ${COLLECTD_HOSTNAME}/onu_${SUBSYSTEM}-${INSTANCE_NAME}/${TYPE}"
  ECHO_TEXT="${ECHO_TEXT} interval=${LOOP_INTERVAL} ${VALUE_TIME}:${VALUE}"
  
  echo -e "${ECHO_TEXT}" | tee -a "${DEBUG_OUTPUT_FILE}"
}

report_diag_value() {
  local CMD=$1
  local REGEX=$2
  shift 2
  report_value "diag" "$CMD" "$REGEX" $@
}

report_cli_value() {
  local CMD=$1
  local REGEX=$2
  shift 2
  report_value "cli" "$CMD" "$REGEX" $@
}

report_onu_collectd() {
  local ONU_SERVER ONU_USERNAME ONU_PASSWORD SEXPECT_SOCKFILE RET_CODE
  config_get ONU_SERVER $1 server
  config_get ONU_USERNAME $1 username
  config_get ONU_PASSWORD $1 password
  config_get ONU_INSTANCE_NAME $1 instance_name
  SEXPECT_SOCKFILE="$(mktemp -t -u "collectd.${PLUGIN_NAME}.XXXXXX")"
  export SEXPECT_SOCKFILE ONU_USERNAME ONU_PASSWORD ONU_SERVER
  report_notification $SEVERITY_OK "Start processing ${ONU_INSTANCE_NAME}"
  enter_cli
  RET_CODE=$?
  if [ "${RET_CODE}" -eq "0" ]; then
    # SYNTAX:
    # report_{cli,diag}_value '<COMMAND>' '<REGEX>' '<CAPTURE_GROUP_NUMBER>' \
    #   '<INSTANCE_NAME>' '<SUBSYSTEM>'  '<DATA_TYPE>'
    # report_cli_value can be run after enter_cli and before enter_diag,
    #  or after exit_diag before exit_cli
    # report_diag_value can be run after enter_diag and before exit_diag
    # enter_diag can be run after enter_cli
    report_cli_value 'cat /proc/uptime' \
      '(\d+\.\d+)\s\d+\.\d+' 1 "${ONU_INSTANCE_NAME}" \
      "system" "uptime"
    enter_diag
    report_diag_value 'pon get transceiver temperature' \
      'Temperature: (-?\d+(|\.\d+))\s+C' 1 "${ONU_INSTANCE_NAME}" \
      "transceiver" "temperature"
    report_diag_value 'pon get transceiver voltage' \
      'Voltage: (\d+(|\.\d+))\s+V' 1 "${ONU_INSTANCE_NAME}" \
      "transceiver" "voltage"
    report_diag_value 'pon get transceiver bias-current' \
      'Bias Current: (\d+(|\.\d+))\s+mA' 1 "${ONU_INSTANCE_NAME}" \
      "transceiver_bias" "current"
    report_diag_value 'pon get transceiver rx-power' \
      'Rx Power: (-?\d+(|\.\d+))\s+dBm' 1 "${ONU_INSTANCE_NAME}" \
      "transceiver_rx" "signal_power"
    report_diag_value 'pon get transceiver tx-power' \
      'Tx Power: (-?\d+(|\.\d+))\s+dBm' 1 "${ONU_INSTANCE_NAME}" \
      "transceiver_tx" "power"
    exit_diag
    exit_cli || true
  else
    report_notification $SEVERITY_FAILURE \
      "Failed connecting ${ONU_INSTANCE_NAME} (${ONU_USERNAME}@${ONU_SERVER})"
  fi
  rm -f $SEXPECT_SOCKFILE
  report_notification $SEVERITY_OK "End processing ${ONU_INSTANCE_NAME}"
}

# Checks
type ${SEXPECT_BIN} >/dev/null || report_notification $SEVERITY_FAILURE \
  "No 'sexpect' binary found. Install it."
type ${TELNET_BIN} >/dev/null || report_notification $SEVERITY_FAILURE \
  "No 'telnet' binary found. Install it."

sleep "${STARTUP_DELAY}s"
# Infinite loop
while true; do
  report_notification $SEVERITY_OK "Loop started"
  config_load "${UCI_CONFIG_NAME}"
  config_foreach report_onu_collectd onu_item
  report_notification $SEVERITY_OK "Loop finished, waiting ${LOOP_INTERVAL}s"
  sleep "${LOOP_INTERVAL}s"
done
