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


