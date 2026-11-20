#!/bin/bash
# shellcheck disable=SC2034

# ============================
# Archon Menu
# (Arrow_key Menu for Archon.sh)
#
#
# Version: 2.4.0
# ============================



# exit from script when a pipe fail
set -o pipfail  


# ---------- Preconditions ----------


SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

ARCHON_SH="$ُSCRIPT_DIR/Archon.sh"

CONFIG_DIR="$SCRIPT_DIR/Archon_Configs"

CONFIG_FILE="$CONFIG_DIR/Archon.conf"

LOG_DIR="$SCRIPT_DIR/Archon_Logs"



# if bash is older than 4 it get error

if (( BASH_VERSINFO[0] < 4 )); then
    echo "[ERROR] Archon Menu needs Bash 4 or newer." >&2
    exit 1

fi


# its meen input & outpu should be for terminal you cant use it is pipeline and cron
if [[ ! -t 0 || ! -t 1 ]]; then
    echo "[ERROR] Archon Menu needs an intractive terminal." >&2
    exit 1
fi


# if the TERM varieble have a value it use that else it replace with dumb
# if teminal doesnt have a essenatial futures the menu will not open
if [[ "${TERM:-dumb}" == "dumb" ]]; then
    echo "[ERROR] Unsupported terminal (TERM=${TERM:-unset})." >&2
    exit 1
fi

if [[ ! -f "$ARCHON_SH" ]]; then
    echo "[ERROR] Archon.sh not found next to this script: $ARCHON_SH" >&2
    exit 1
fi


# it find a first line that (# Version: ) writed for input and then for output it will delete a (# Version: ) and it just a number 
ARCHON_VERSION="$(grep -m1 '^# Version:' "$ARCHON_SH" | sed 's/^# Version: *//')"

# if the (# Vesion: ) didnt find the out put will be (?)
ARCHON_VERSION="${ARCHON_VERSION:-?}"




# if the user was root and use sudo then it will find the user data in passwd and it will get the home dir of that user
# else REAL_NAME is eq $HOME or /
# in the last step it check if REAL_HOME is a real dir or not if id isnt a dir RAEL_HOME will eq / 
if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" ]]; then
    REAL_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"

else 
    REAL_HOME="${HOME:-/}"
fi
[[ -d "$REAL_HOME" ]] || REAL_HOME="/"



