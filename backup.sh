#!/bin/bash


# ===============================
# Linux Automated Backup
#
# Version: 1.0.0
# ===============================
#
#
#
# ---------- Configuration ----------


SOURCE_DIRS=(
	"$HOME/Documents"
	"$HOME/Downloads"
)



BACKUP_DIR="$HOME/projects/LinuxBackup/backups"

DATE=$(date +"%Y-%m-%d_%H:%M:%S")

BACKUP_FILE="$BACKUP_DIR/backup_$DATE.tar.gz"


# ---------- Create Backup Directory ----------

mkdir -p "$BACKUP_DIR"


# ---------- Validate Source Directories ----------


for DIR in "${SOURCE_DIRS[@]}"; do
	if [[ ! -d "$DIR" ]]; then
		echo "ERROR: Sourece directory not found: $DIR"
		exit 1
	fi
done


# ---------- Create Backup ----------

tar -czf "$BACKUP_FILE" -C / "${SOURCE_DIRS[@]#/}"

# ---------- Check Backup Result ----------

if [[ $? -eq 0 ]]; then
	echo "Backup completed successfully!"
	echo "Backupfile: $BACKUP_FILE"
else
	echo "ERROR:  backup failed!"
	exit 1
fi



