#!/bin/bash


# ===============================
# Linux Automated Backup
#
# Version: 1.0.1
# ===============================
#

set -Eeuo pipefail



# ---------- Configuration ----------


SOURCE_DIRS=(
	"$HOME/Documents"
	"$HOME/Downloads"
)



BACKUP_DIR="$HOME/projects/LinuxBackup/backups"

DATE=$(date +"%Y-%m-%d_%H:%M:%S")

BACKUP_FILE="$BACKUP_DIR/backup_$DATE.tar.gz"




# ---------- Create Log ----------

log() {
	"[INFO] $1"
}

# ---------- Validate Source Directories ----------

validate_source() {
	VALIDATED_DIRS=()
	for DIR in "${SOURCE_DIRS[@]}"; do
		if [[ ! -d "$DIR" ]]; then
			error "Source directiry not found: $DIR"
			return 1
		fi

		if [[ "$DIR" == "/" ]]; then
			error "Backing up the root directory is not supported."
			return 1
		fi
		
		REAL_DIR=$(realpatch -e "$DIR")
		VALIDATED_DIRS+=("$REAL_DIR")
	done
}




# ---------- Create Backup Directory ----------

create_backup_directory() {
	mkdir -p "$BACKUP_DIR"
	BACKUP_DIR=$(realpath -e "$BACKUO_DIR")
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
	tar -czf "$BACKUP_ّFILE" -C / -- "${VALIDATED_DIRS[@]#/}"
	log "Backup archive created."
}



# ---------- Verify Backup ----------

verify_backup() {
	log "Verifying backup archive ..."
	if [[ ! -s "$BACKUP_FILE" ]]; then
		error "Backup archive is missing or empty."
		return 1
	fi

	if tar -tzf "$BACKUP_FILE" > /dev/null; then
		log "Backup archive verified successfully."

	else
		log "Backup archive verified failed."
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
	varify_backup

	log "Backup Completed successfully!"
	log "Backup fille: $BACKUP_FILE"
}





main



