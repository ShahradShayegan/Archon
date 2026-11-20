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



# ---------- Home Diretory of the real users (also when they start with sudo) ----------


# if the user was root and use sudo then it will find the user data in passwd and it will get the home dir of that user
# else REAL_NAME is eq $HOME or /
# in the last step it check if REAL_HOME is a real dir or not if id isnt a dir RAEL_HOME will eq / 
if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" ]]; then
    REAL_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"

else 
    REAL_HOME="${HOME:-/}"
fi
[[ -d "$REAL_HOME" ]] || REAL_HOME="/"



# ---------- Colors and Box Characters ----------

ESC=$'\e'
C_RESET="${ESC}[0m"

if [[ -z "${NO_COLOR:-}" ]]; then
	C_SCREEN="${ESC}[0;97;44m"        # white on blue (screen background)
	C_BOX="${ESC}[0;30;47m"           # black on white (menu box)
	C_TITLE_DEFAULT="${ESC}[1;34;47m" # bold blue on white
	C_TITLE_ERR="${ESC}[1;31;47m"     # bold red on white
	C_TITLE_OK="${ESC}[1;32;47m"      # bold green on white
	C_SEL="${ESC}[1;97;44m"           # bold white on blue (selected row)
	C_INPUT="${ESC}[1;30;46m"         # bold black on cyan (input field)
	C_SHADOW="${ESC}[0;30;40m"        # black (drop shadow)

else
	C_SCREEN=""
	C_BOX=""
	C_TITLE_DEFAULT="${ESC}[1m"
	C_TITLE_ERR="${ESC}[1m"
	C_TITLE_OK="${ESC}[1m"
	C_SEL="${ESC}[7m"
	C_INPUT="${ESC}[4m"
	C_SHADOW=""
fi

TITLE_COLOR="$C_TITLE_DEFAULT"


# for this i use AI but it will make a border for Title.
if [[ "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" =~ [Uu][Tt][Ff]-?8 ]]; then
	B_TL='╔'; B_TR='╗'; B_BL='╚'; B_BR='╝'; B_H='═'; B_V='║'; B_ML='╠'; B_MR='╣'; MARK='▶'
else
	B_TL='+'; B_TR='+'; B_BL='+'; B_BR='+'; B_H='-'; B_V='|'; B_ML='+'; B_MR='+'; MARK='>'
fi


