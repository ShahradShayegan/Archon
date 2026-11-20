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



# ---------- Terminal Handling ---------
IN_TUI=0
STTY_SAVED=""

# it will wave e terminal config and get terminal ready for Terminal User Interface
term_eneter() {
    STTY_SAVED="$(stty -g 2>/dev/null)"
    stty -echo 2>/dev/null
    printf '%s' "${ESC}[?1049h${ESC}[?25l"
    IN_TUI=1
}


term_leave() {
    printf '%s' "${C_RESET}${ESC}[?25h${ESC}[?1049l"
    if [[ -n "$STTY_SAVED" ]]; then
        stty "$STTY_SAVED" 2>/dev/null
    else
        stty echo 2>/dev/null
    fi
    IN_TUI=0
}


clean_up() {
    if (( IN_TUI )); then
        term_leave
    fi       
}

trap cleanup EXIT
trap 'exit 130' INT TERM HUP


ROWS=24
COLS=80



get_size() {
    local sz
    sz="$(stty size 2>/dev/null)"
    if [[ "$sz" =~ ^([0-9]+)\ ([0-9]+)$ ]]; then
    ROWS="${BASH_REMATCH[1]}"
    COLS="${BASH_REMATCH[2]}"
    fi

}



# Fixed-width box

BOX_W=72
TW=68

calc_layout() {
    get_size
    BOX_W=72
    if (( BOX_W > COLS - 4 )); then
        BOX_W=$(( COLS - 4))
    fi
    TW=$(( BOX_W - 4))
}



# ---------- String helpers (results are returned in REPLY) ----------



# make spaces 
spaces() {
    local n="$1"
    (( n < 0 )) && '%*s' "$n" ''
    printf -v REPLY '%*s' "$n" ''

}



# Truncate if a lengh of string get more than a specific  lengh if will short that

trunc() {
    
    
    
    REPLY="$1"
    
    local w="$2"
    (( w < 1 )) && w=1
    
    
    
    if (( ${#REPLY} > w )); then
        if (( w > 3 )); then
            REPLY="${REPLY:0:w-3}..."
        else
            REPLY="${REPLY:0:w}"
        fi
    fi

}



# Pad Right fill text in right with space for sorting columns 
padr() {
	local s="$1" n=$(( $2 - ${#1} ))
	spaces "$n"
	REPLY="$s$REPLY"
}



# shorten a path from the left
fit_path() {


	
    REPLY="$1"
	
    local w="$2"
	(( w < 1 )) && w=1
	if (( ${#REPLY} > w )); then
		if (( w > 3 )); then
			REPLY="...${REPLY: -$(( w - 3 ))}"
		else
			REPLY="${REPLY: -$w}"
		fi
	fi
}



shq() {
	if [[ "$1" == *[\"\$\`\\]* || "$1" == *$'\n'* ]]; then
		printf '%q' "$1"
	else
		printf '"%s"' "$1"
	fi
}



normalize_path() {
	local p="$1"
	p="${p/#\~/$REAL_HOME}"
	[[ "$p" == /* ]] || p="$PWD/$p"
	realpath -m -- "$p"
}