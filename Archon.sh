#!/bin/bash


# ===============================
#َ Archon
#
# Version: 1.1.0
# ===============================
#

set -Eeuo pipefail





# ---------- Colors ----------
#
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
	RED=$'\033[0;31m'
	GREEN=$'\033[0;32m'
	YELLOW=$'\033[0;33m'
	BLUE=$'\033[0;34m'
	BOLD=$'\033[1m'
	RESET=$'\033[0m'
else 
	RED=""
	GREEN=""
	YELLOW=""
	BLUE=""
	BOLD=""
	RESET=""
fi



# ---------- Create Log ----------

log() {
	echo "${BLUE}[INFO]${RESET} $1"
}


success() {
	echo "${GREEN}[OK]${RESET} $1"
}


warn() {
	echo "${YELLOW}[WARN]${RESET} $1" >&2
}


error() {
	if [[ -t 2 && -z "${NO_COLOR:-}" ]]; then 
		echo "${RED}[ERROR]${RESET} $1" >&2
	else
		echo "[ERROR] $1" >&2
	fi
}

# ---------- Load Configuration ----------

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
CONFIG_FILE="$SCRIPT_DIR/Archon_Configs/Archon.conf"

if [[ ! -f "$CONFIG_FILE" ]]; then
	error "Configuration file not found: $CONFIG_FILE"
	exit 1
fi

source "$CONFIG_FILE"



# ---------- Validate Configuration ----------
if ! declare -p  SOURCE_DIRS >/dev/null 2>&1; then
	error "SOURCE_DIRS is not defined in Configuration."
	exit 1
fi


if [[ ${#SOURCE_DIRS[@]} == 0 ]]; then
	error "No source directories configured."
	exit 1
fi

: "${BACKUP_DIR:?BACKUP_DIR is not defined in configuration}"

DATE=$(date +"%Y-%m-%d_%H:%M:%S")
BACKUP_FILE="$BACKUP_DIR/backup_$DATE.tar.gz"




# ---------- Validate Source Directories ----------

validate_sources() {
	VALIDATED_DIRS=()
	for DIR in "${SOURCE_DIRS[@]}"; do
		if [[ ! -d "$DIR" ]]; then
			error "Source directiry not found: $DIR"
			return 1
		fi
		
		REAL_DIR=$(realpath -e "$DIR")
		
		
		if [[ "$REAL_DIR" == "/" ]]; then
			error "Backing up the root directory is not supported."
			return 1
		fi

		VALIDATED_DIRS+=("$REAL_DIR")
		log "Source directory: $REAL_DIR"
	done
}




# ---------- Create Backup Directory ----------

create_backup_directory() {
	mkdir -p "$BACKUP_DIR"
	BACKUP_DIR=$(realpath -e "$BACKUP_DIR")
	log "Backup directory: $BACKUP_DIR"
}


# ---------- Validate Backup Location ----------

validate_backup_location() {
	for DIR in "${VALIDATED_DIRS[@]}"; do
		if [[ "$BACKUP_DIR" ==	"$DIR" || "$BACKUP_DIR" == "$DIR/"* ]]; then
			error "Backup directory is inside asource directory: $DIR"
			return 1
		fi
	done
}



# ---------- Create Backup ----------

create_backup() {
	log "Starting backup ..."
	tar -czf "$BACKUP_FILE" -C / -- "${VALIDATED_DIRS[@]#/}"
	success "Backup archive created."
}



# ---------- Verify Backup ----------

verify_backup() {
	log "Verifying backup archive ..."
	if [[ ! -s "$BACKUP_FILE" ]]; then
		error "Backup archive is missing or empty."
		return 1
	fi

	if tar -tzf "$BACKUP_FILE" > /dev/null; then
		success "Backup archive verified successfully."

	else
		error "Backup archive verified failed."
		return 1
	fi
}





# ---------- Main ----------
main() {
	log "Starting Linux Backup System."
	
	validate_sources
	create_backup_directory
	validate_backup_location
	create_backup
	verify_backup

	success "Backup Completed successfully!"
	log "Backup fille: ${BOLD}$BACKUP_FILE${RESET}"
}





main



