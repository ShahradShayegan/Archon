# Archon

**Archon** is a simple, safe Bash script that backs up one or more directories into a compressed `tar.gz` archive and verifies the result.

**Current version:** 1.2.0

> **Status:** early development. The goal is a fully automated backup tool (scheduling, retention, compression options), built step by step.

---

## Features

- Back up multiple source directories in a single archive
- Compressed output (`.tar.gz`) with a timestamped filename
- Automatic creation of the backup directory
- Safety checks before anything is written:
  - Configuration file and required settings exist
  - Every source directory exists
  - Backing up `/` (the root directory) is refused
  - The backup directory cannot be inside a source directory
- Archive verification after creation (non-empty and readable)
- Colored, leveled console output (`INFO`, `OK`, `WARN`, `ERROR`)
- Strict Bash mode (`set -Eeuo pipefail`) to fail fast on errors

---

## Requirements

- Linux
- Bash 4+
- `tar`, `gzip`, `realpath` (part of GNU coreutils, available on virtually all distributions)

---

## Project Structure

```
Archon/
├── Archon.sh          # Main script
├── Archon_Configs/    # Configuration files
│   └── Archon.conf
├── Archon_Backups/    # Default location for backup archives
├── Archon_Logs/       # Log files (planned)
└── README.md
```

---

## Installation

```bash
git clone https://github.com/ShahradShayegan/Archon.git
cd Archon
chmod +x Archon.sh
```

---

## Configuration

Edit `Archon_Configs/Archon.conf`:

```bash
# Directories to back up (use absolute paths)
SOURCE_DIRS=("/home/user/documents" "/etc")

# Where backup archives will be stored
BACKUP_DIR="/home/user/Archon/Archon_Backups"
```

| Variable      | Required | Description                                      |
|---------------|----------|--------------------------------------------------|
| `SOURCE_DIRS` | Yes      | Bash array of directories to include in the backup |
| `BACKUP_DIR`  | Yes      | Destination directory for the archive            |

---

## Usage

```bash
./Archon.sh
```

Example output:

```
[INFO] Starting Archon.
[INFO] Source directory: /home/user/documents
[INFO] Source directory: /etc
[INFO] Backup directory: /home/user/Archon/Archon_Backups
[INFO] Starting backup ...
[OK] Backup archive created.
[INFO] Verifying backup archive ...
[OK] Backup archive verified successfully.
[OK] Backup completed successfully!
[INFO] Backup file: /home/user/Archon/Archon_Backups/backup_2026-11-15_14-30-05.tar.gz
```

### Disabling colors

Colors are enabled only when output goes to a terminal. To turn them off explicitly:

```bash
NO_COLOR=1 ./Archon.sh
```

---

## Restoring a Backup

Archives store paths relative to `/`. To inspect or restore safely, extract into a temporary directory first:

```bash
mkdir -p /tmp/restore
tar -xzf /home/user/Archon/Archon_Backups/backup_<timestamp>.tar.gz -C /tmp/restore
```

To list the contents without extracting:

```bash
tar -tzf /home/user/Archon/Archon_Backups/backup_<timestamp>.tar.gz
```

---

## Roadmap

- [x] Multi-directory backup with `tar.gz` compression
- [x] Configuration file
- [x] Input and location validation
- [x] Archive verification
- [x] Colored console logs
- [x] Log files written to `Archon_Logs/` (created automatically)
- [ ] Configurable archive prefix and date format
- [ ] Automatic scheduled backups (cron / systemd timer)
- [ ] Retention policy (delete old backups automatically)
- [ ] Exclude patterns
- [ ] Selectable compression (gzip, xz, zstd)
- [ ] Checksums for backup integrity
- [ ] Notifications (email / webhook) on success or failure

---

## Changelog

### 1.1.0
- Colored, leveled console logs (`INFO`, `OK`, `WARN`, `ERROR`) with `NO_COLOR` support
- Backup directory is now logged at startup
- Fixed typos in log messages

### 1.0.1
- Initial release: multi-directory `tar.gz` backup with validation and verification

### 1.2.0
- Logs are saved to daily files in `Archon_Logs/` (directory created automatically)
- Works with or without `sudo`: ownership is restored to the invoking user, with a temp-directory fallback
- Archive filenames no longer contain `:`
- Fixed hidden characters and typos in the script

---

## Safety Notes

- Always test a restore before relying on a backup.
- Keep backups on a different disk or machine than the original data whenever possible.
- Reading some system directories (such as `/etc`) may require running the script with `sudo`.


