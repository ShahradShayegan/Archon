# Archon

**Archon** is a simple, safe Bash script that backs up one or more directories into a compressed `tar.gz` archive and verifies the result.

**Current version:** 1.4.0

> **Status:** early development. The goal is a fully automated backup tool (scheduling, retention, compression options), built step by step.

---

## Features

- Back up multiple source directories in a single archive
- Compressed output (`.tar.gz`) with a timestamped filename
- Configurable filename prefix and timestamp format
- Optional retention: keep only the newest N archives
- Automatic creation of the backup directory
- Safety checks before anything is written:
  - Configuration file and required settings exist
  - Every source directory exists
  - Backing up `/` (the root directory) is refused
  - The backup directory cannot be inside a source directory
  - Filename settings are validated (no `/`, no spaces)
- Archive verification after creation (non-empty and readable)
- Colored, leveled console output (`INFO`, `OK`, `WARN`, `ERROR`)
- Log files with timestamps, written to `Archon_Logs/`
- Works with or without `sudo`: files it creates are handed back to the invoking user
- Strict Bash mode (`set -Eeuo pipefail`) to fail fast on errors

---

## Requirements

- Linux
- Bash 4+
- `tar`, `gzip`, `realpath`, `find`, `sort` (GNU coreutils and findutils, available on virtually all distributions)

---

## Project Structure

```
Archon/
├── Archon.sh          # Main script
├── Archon_Configs/    # Configuration files
│   └── Archon.conf
├── Archon_Backups/    # Default location for backup archives
├── Archon_Logs/       # Log files (created automatically)
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
# Required: directories to back up (use absolute paths)
SOURCE_DIRS=("/home/user/documents" "/etc")

# Required: where backup archives will be stored
BACKUP_DIR="/home/user/Archon/Archon_Backups"

# Optional: archive filename prefix (letters, digits, . _ - only)
BACKUP_PREFIX="backup"

# Optional: timestamp format used in the filename (see `man date`)
DATE_FORMAT="%Y-%m-%d_%H-%M-%S"

# Optional: keep only the newest N archives (0 = keep everything)
KEEP_LAST=0
```

| Variable        | Required | Default             | Description                                                                          |
|-----------------|----------|---------------------|--------------------------------------------------------------------------------------|
| `SOURCE_DIRS`   | Yes      | -                   | Bash array of directories to include in the backup                                   |
| `BACKUP_DIR`    | Yes      | -                   | Destination directory for the archive                                                |
| `BACKUP_PREFIX` | No       | `backup`            | Prefix of the archive filename                                                       |
| `DATE_FORMAT`   | No       | `%Y-%m-%d_%H-%M-%S` | `date` format for the timestamp in the filename                                      |
| `KEEP_LAST`     | No       | `0` (keep all)      | Keep only the newest N archives named `<BACKUP_PREFIX>_*.tar.gz` in `BACKUP_DIR`     |

The archive is named `<BACKUP_PREFIX>_<timestamp>.tar.gz`, for example `docs_20261119.tar.gz`. Invalid values (such as a prefix containing `/`, or a non-numeric `KEEP_LAST`) are rejected before anything is written.

### Retention

When `KEEP_LAST` is greater than 0, older archives are deleted after each successful backup:

- Only files named `<BACKUP_PREFIX>_*.tar.gz` directly inside `BACKUP_DIR` are considered. Other files, other prefixes and subdirectories are never touched.
- The archive that was just created is never removed.
- Archives are ordered by modification time, newest first.
- Nothing is deleted if the backup or its verification fails.
- Retention is disabled by default.

Use a separate `BACKUP_DIR` (or a prefix that is not the start of another prefix) for each setup. For example, a `backup` prefix would also match files named `backup_docs_*.tar.gz`.

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
[INFO] Backup file: /home/user/Archon/Archon_Backups/backup_2026-11-19_14-30-05.tar.gz
```

With `KEEP_LAST=3`, extra lines appear after verification:

```
[INFO] Retention: keeping the newest 3 archives named backup_*.tar.gz
[INFO] Removed old backup: /home/user/Archon/Archon_Backups/backup_2026-11-16_09-00-00.tar.gz
[INFO] Retention finished: 1 removed
```

### Disabling colors

Colors are enabled only when output goes to a terminal. To turn them off explicitly:

```bash
NO_COLOR=1 ./Archon.sh
```

---

## Logs

Every run is logged to `Archon_Logs/archon_YYYY-MM-DD.log`. The directory is created automatically, and several runs on the same day are appended to the same file. Log files contain timestamps and no color codes:

```
2026-11-19 14:30:05 [INFO] Starting Archon.
2026-11-19 14:30:05 [INFO] Source directory: /home/user/documents
2026-11-19 14:30:07 [OK] Backup archive created.
```

If `Archon_Logs/` is not writable, Archon falls back to a per-user directory in `/tmp` and prints a warning. If no location is writable, file logging is disabled and the backup still runs.

### Running with sudo

Some directories (such as `/etc`) can only be read by root. When Archon is started with `sudo`, the log files, the new archive, and a backup directory it had to create are handed back to the invoking user, so the next run without `sudo` still works.

---

## Restoring a Backup

Archives store paths relative to `/`. To inspect or restore safely, extract into a temporary directory first:

```bash
mkdir -p /tmp/restore
tar -xzf /home/user/Archon/Archon_Backups/<prefix>_<timestamp>.tar.gz -C /tmp/restore
```

To list the contents without extracting:

```bash
tar -tzf /home/user/Archon/Archon_Backups/<prefix>_<timestamp>.tar.gz
```

---

## Roadmap

- [x] Multi-directory backup with `tar.gz` compression
- [x] Configuration file
- [x] Input and location validation
- [x] Archive verification
- [x] Colored console logs
- [x] Log files written to `Archon_Logs/` (created automatically)
- [x] Configurable archive prefix and date format
- [x] Retention policy (keep the newest N backups)
- [ ] Automatic scheduled backups (cron / systemd timer)
- [ ] Exclude patterns
- [ ] Selectable compression (gzip, xz, zstd)
- [ ] Checksums for backup integrity
- [ ] Notifications (email / webhook) on success or failure

---

## Changelog

### 1.4.0
- Added optional `KEEP_LAST` retention: delete older archives after a successful backup
- Disabled by default; only affects archives matching the configured prefix

### 1.3.0
- Added optional `BACKUP_PREFIX` and `DATE_FORMAT` settings to the config file
- Both values are validated; the defaults keep the previous filename format

### 1.2.0
- Logs are saved to daily files in `Archon_Logs/` (directory created automatically)
- Works with or without `sudo`: ownership is restored to the invoking user, with a temp-directory fallback
- Archive filenames no longer contain `:`
- Fixed hidden characters and typos in the script

### 1.1.0
- Colored, leveled console logs (`INFO`, `OK`, `WARN`, `ERROR`) with `NO_COLOR` support
- Backup directory is now logged at startup
- Fixed typos in log messages

### 1.0.1
- Initial release: multi-directory `tar.gz` backup with validation and verification

---

## Safety Notes

- Always test a restore before relying on a backup.
- Keep backups on a different disk or machine than the original data whenever possible.
- Reading some system directories (such as `/etc`) may require running the script with `sudo`.
- Retention permanently deletes old archives. Start with a larger `KEEP_LAST` value and check the log before lowering it.
