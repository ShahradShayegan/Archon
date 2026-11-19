#!/bin/bash


# ===============================
# Archon
#
# Version: 1.4.0
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
#	BOLD=$'\033[1m'
	RESET=$'\033[0m'
else 
	RED=""
	GREEN=""
	YELLOW=""
	BLUE=""
#	BOLD=""
	RESET=""
fi

# ---------- Paths & Logs File ----------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
LOG_DIR="$SCRIPT_DIR/Archon_Logs"
LOG_FILE="$LOG_DIR/archon_$(date +"%Y-%m-%d").log"




# when run via sudo, give ownership back to the real user
fix_ownership() {
	if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" ]]; then
		chown -R "$SUDO_USER":"$(id -gn "$SUDO_USER")" "$@" 2>/dev/null || true 

	fi
}



init_logging() {
	if mkdir -p "$LOG_DIR" 2>/dev/null && touch "$LOG_FILE" 2>/dev/null; then
		fix_ownership "$LOG_DIR"
		return 0
	fi

	#fallback: temp directory (per user)
	local fallback_dir fallback_file
	fallback_dir="${TMPDIR:-/tmp}/Archon_Logs_$(id -u)"
	fallback_file="$fallback_dir/archon_$(date +"%Y-%m-%d").log"

	if mkdir -p "$fallback_dir" 2>/dev/null && touch "$fallback_file" 2>/dev/null; then
		echo "[WARN] Cannot write to $LOG_DIR. Logging to $fallback_file instead." >&2
		LOG_DIR="$fallback_dir"
		LOG_FILE="$fallback_file"
		return 0
	fi

	echo "[WARN] File logging is disabled (no writable log location)." >&2
	LOG_FILE=""
}

init_logging












# ---------- Create Log ----------
write_log() {
	[[ -n  "$LOG_FILE" ]] || return 0
	printf '%s [%s] %s\n' "$(date +"%Y-%m-%d %H:%M:%S")" "$1" "$2" 2>/dev/null >>  "$LOG_FILE" || true
}

	





log() {
	echo "${BLUE}[INFO]${RESET} $1"
	write_log "INFO" "$1"

}


success() {
	echo "${GREEN}[OK]${RESET} $1"
	write_log "OK" "$1"
}


warn() {
	echo "${YELLOW}[WARN]${RESET} $1" >&2
	write_log "WARN" "$1"
}



error() {
	if [[ -t 2 && -z "${NO_COLOR:-}" ]]; then 
		echo "${RED}[ERROR]${RESET} $1" >&2
	else
		echo "[ERROR] $1" >&2
	fi
	write_log "ERROR" "$1"
}

# ---------- Load Configuration ----------


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





# ---------- Date & Prefix Format ----------



BACKUP_PREFIX="${BACKUP_PREFIX:-backup}"
DATE_FORMAT="${DATE_FORMAT:-%Y-%m-%d_%H-%M-%S}"


if [[ ! "$BACKUP_PREFIX" =~ ^[A-Za-z0-9._-]+$ ]]; then
	error "BACKUP_PREFIX may only contain letters, digits, '.', '_', and '-': $BACKUP_PREFIX"
	exit 1
fi 

DATE=$(date +"$DATE_FORMAT")
if [[ -z "$DATE" || "$DATE" =~ [[:space:]/] ]]; then
	error "DATE_FORMAT produces an invalid filename part: $DATE_FORMAT"
	exit 1
fi


# ---------- Keep Last Check ----------

KEEP_LAST="${KEEP_LAST:-0}"

if [[ ! "$KEEP_LAST" =~ ^[0-9]+$ ]]; then
	error "KEEP_LAST must be a non-negative integer: $KEEP_LAST"
	exit 1

fi


KEEP_LAST=$((10#$KEEP_LAST))









# ---------- Validate Source Directories ----------

validate_sources() {
	VALIDATED_DIRS=()
	for DIR in "${SOURCE_DIRS[@]}"; do
		if [[ ! -d "$DIR" ]]; then
			error "Source directory not found: $DIR"
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
	local created=0
	[[ -d "$BACKUP_DIR" ]] || created=1


	mkdir -p "$BACKUP_DIR"
	BACKUP_DIR=$(realpath -e "$BACKUP_DIR")
	BACKUP_FILE="$BACKUP_DIR/${BACKUP_PREFIX}_$DATE.tar.gz"

 	# only change ownership of a directory we just created
	if [[ $created -eq 1 ]]; then 
		fix_ownership "$BACKUP_DIR"
	fi

	log "Backup directory: $BACKUP_DIR"
}


# ---------- Validate Backup Location ----------

validate_backup_location() {
	for DIR in "${VALIDATED_DIRS[@]}"; do
		if [[ "$BACKUP_DIR" ==	"$DIR" || "$BACKUP_DIR" == "$DIR/"* ]]; then
			error "Backup directory is inside a source directory: $DIR"
			return 1
		fi
	done
}



# ---------- Create Backup ----------

create_backup() {
	log "Starting backup ..."
	tar -czf "$BACKUP_FILE" -C / -- "${VALIDATED_DIRS[@]#/}"
	fix_ownership "$BACKUP_FILE"
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
		error "Backup archive verification failed."
		return 1
	fi
}


# ---------- Apply Retention ----------

apply_retention() {
	[[ "$KEEP_LAST" -gt 0 ]] || return 0

	log "Retention: keeping the newest $KEEP_LAST archives named ${BACKUP_PREFIX}_*.tar.gz"

	local entry file count=0 removed=0

	while IFS= read -r -d '' entry; do
		file="${entry#* }"
		count=$((count + 1))


		[[ $count -gt $KEEP_LAST ]] || continue
		[[ "$file" != "$BACKUP_FILE" ]] || continue     # never delete the new archive


		if rm -f -- "$file"; then
			log "Removed old backup: $file"
			removed=$((removed + 1))

		else
			warn "Could not remove old backup: $file"

		fi
	done < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name "${BACKUP_PREFIX}_*.tar.gz" -printf '%T@ %p\0' | sort -z -rn)

	log "Retention finished: $removed removed"
}



















# ---------- Main ----------
main() {
	log "Starting Archon."
	
	validate_sources
	create_backup_directory
	validate_backup_location
	create_backup
	verify_backup
	apply_retention

	success "Backup completed successfully!"
	log "Backup file: $BACKUP_FILE"
}





main



