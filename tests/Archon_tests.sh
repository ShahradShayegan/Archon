#!/bin/bash

# ===============================
# Archon - Automated Test Suite
#
# Usage:
#   ./tests/run_tests.sh              # test ../Archon.sh
#   ./tests/run_tests.sh path/to/Archon.sh
#   sudo ./tests/run_tests.sh         # also runs the sudo/ownership tests
#
# Every test runs on a COPY of the script inside a temporary sandbox,
# so your real config, logs and backups are never touched.
# ===============================

set -uo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR="$(dirname "$TESTS_DIR")"
if [[ -n "${1:-}" ]]; then
	SCRIPT_UNDER_TEST="$1"
elif [[ -f "$PROJECT_DIR/Archon.sh" ]]; then
	SCRIPT_UNDER_TEST="$PROJECT_DIR/Archon.sh"
else
	SCRIPT_UNDER_TEST="$TESTS_DIR/Archon.sh"
fi

if [[ ! -f "$SCRIPT_UNDER_TEST" ]]; then
	echo "[ERROR] Script not found: $SCRIPT_UNDER_TEST" >&2
	exit 2
fi

# ---------- Colors (only on a terminal) ----------

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
	RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'
	BOLD=$'\033[1m'; RESET=$'\033[0m'
else
	RED=""; GREEN=""; YELLOW=""; BOLD=""; RESET=""
fi

ESC=$'\033'

# ---------- Work area ----------

WORK="$(realpath "$(mktemp -d)")"

cleanup() {
	chmod -R u+rwX "$WORK" 2>/dev/null || true
	rm -rf "$WORK"
}
trap cleanup EXIT

# ---------- Test framework ----------

PASS=0
FAIL=0
SKIP=0
CURRENT=""
FAILED=()
SANDBOX_COUNT=0

section() {
	CURRENT="$1"
	echo
	echo "${BOLD}$1${RESET}"
}

pass() { PASS=$((PASS + 1)); echo "  ${GREEN}PASS${RESET} $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  ${RED}FAIL${RESET} $1"; FAILED+=("$CURRENT -> $1"); }
skip() { SKIP=$((SKIP + 1)); echo "  ${YELLOW}SKIP${RESET} $1"; }

# expect "description" command [args...]
expect() {
	local desc="$1"
	shift
	if "$@" >/dev/null 2>&1; then
		pass "$desc"
	else
		fail "$desc"
	fi
}

# ---------- Assertion helpers (use the globals set by run) ----------

rc_is()        { [[ "$RC" -eq "$1" ]]; }
rc_not_zero()  { [[ "$RC" -ne 0 ]]; }
contains()     { [[ "$ALL" == *"$1"* ]]; }
not_contains() { [[ "$ALL" != *"$1"* ]]; }
no_escape()    { [[ "$ALL" != *"$ESC"* ]]; }
has_escape()   { [[ "$ALL" == *"$ESC"* ]]; }
file_exists()  { [[ -e "$1" ]]; }
file_missing() { [[ ! -e "$1" ]]; }
dir_exists()   { [[ -d "$1" ]]; }
owner_is()     { [[ "$(stat -c %U "$1" 2>/dev/null)" == "$2" ]]; }
arch_has()     { tar -tzf "$ARCH" 2>/dev/null | grep -- "$1" >/dev/null; }
arch_no_abs()  { ! tar -tzf "$ARCH" 2>/dev/null | grep '^/' >/dev/null; }
name_ok()      { [[ "$(basename "$ARCH")" =~ ^backup_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}\.tar\.gz$ ]]; }
log_has_ts()   { grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} \[INFO\]' "$1"; }
log_no_esc()   { ! grep -q "$ESC" "$1"; }
log_has()      { grep -q -- "$2" "$1"; }

# ---------- Sandbox helpers ----------

# Fresh sandbox with a copy of the script, a config dir and sample data
new_sandbox() {
	SANDBOX_COUNT=$((SANDBOX_COUNT + 1))
	SB="$WORK/t$SANDBOX_COUNT"
	D="$SB/data"
	OUTDIR="$SB/out"
	mkdir -p "$SB/Archon_Configs" "$SB/tmp" "$D/src1" "$D/src2" "$D/my files"
	cp "$SCRIPT_UNDER_TEST" "$SB/Archon.sh"
	echo "one"   > "$D/src1/a.txt"
	echo "two"   > "$D/src2/b.txt"
	echo "space" > "$D/my files/c.txt"
	ARCH=""
}

# q "a" "b"  ->  "a" "b"   (builds the content of a bash array)
q() { printf '"%s" ' "$@"; }

# setconf '<array content>' '<backup dir>'
setconf() {
	printf 'SOURCE_DIRS=(%s)\nBACKUP_DIR="%s"\n' "$1" "$2" > "$SB/Archon_Configs/Archon.conf"
}

TIMEOUT_CMD=()
if command -v timeout >/dev/null 2>&1; then
	TIMEOUT_CMD=(timeout "${RUN_TIMEOUT:-60}")
fi

# run [ENV=value ...]  ->  sets OUT, ERR, ALL, RC
run() {
	OUT="$(cd "$SB" && ${TIMEOUT_CMD[@]+"${TIMEOUT_CMD[@]}"} env TMPDIR="$SB/tmp" "$@" bash ./Archon.sh 2>"$SB/stderr.txt")"
	RC=$?
	ERR="$(<"$SB/stderr.txt")"
	ALL="$OUT"$'\n'"$ERR"
}

# run_tty [ENV=value ...]  ->  like run, but under a pseudo-terminal
run_tty() {
	OUT="$(cd "$SB" && env TMPDIR="$SB/tmp" "$@" script -qec "bash ./Archon.sh" /dev/null </dev/null 2>&1)"
	RC=$?
	ERR=""
	ALL="$OUT"
}

# find_arch <dir> [prefix]  ->  sets ARCH to the first archive named <prefix>_*.tar.gz
find_arch() {
	ARCH="$(find "$1" -maxdepth 1 -name "${2:-backup}_*.tar.gz" 2>/dev/null | head -1)"
}

today_log() { echo "$SB/Archon_Logs/archon_$(date +%Y-%m-%d).log"; }

can_script() { command -v script >/dev/null 2>&1; }

echo "${BOLD}Archon test suite${RESET}"
echo "Script under test: $SCRIPT_UNDER_TEST"
echo "Version header:    $(grep -m1 '^# Version:' "$SCRIPT_UNDER_TEST" | sed 's/^# Version: *//')"
echo "Sandbox:           $WORK"
echo "Running as:        $(id -un) (uid $EUID)"


# =====================================================================
# 1. BACKUP
# =====================================================================

section "T01 Basic backup with multiple source directories"
new_sandbox
setconf "$(q "$D/src1" "$D/src2")" "$OUTDIR"
run
find_arch "$OUTDIR"
expect "exit code is 0"                         rc_is 0
expect "success message is printed"             contains "Backup completed successfully"
expect "archive file was created"               file_exists "$ARCH"
expect "archive name matches backup_YYYY-MM-DD_HH-MM-SS.tar.gz" name_ok
expect "archive contains src1/a.txt"            arch_has "src1/a.txt"
expect "archive contains src2/b.txt"            arch_has "src2/b.txt"
expect "archive paths have no leading slash"    arch_no_abs

section "T02 Backup directory is created automatically (nested)"
new_sandbox
setconf "$(q "$D/src1")" "$SB/new/nested/out"
run
find_arch "$SB/new/nested/out"
expect "exit code is 0"                         rc_is 0
expect "nested backup directory was created"    dir_exists "$SB/new/nested/out"
expect "archive exists inside it"               file_exists "$ARCH"

section "T03 Source path containing spaces"
new_sandbox
setconf "$(q "$D/my files")" "$OUTDIR"
run
find_arch "$OUTDIR"
expect "exit code is 0"                         rc_is 0
expect "archive contains 'my files/c.txt'"      arch_has "my files/c.txt"

section "T04 Restore and compare"
new_sandbox
setconf "$(q "$D/src1" "$D/src2")" "$OUTDIR"
run
find_arch "$OUTDIR"
mkdir -p "$SB/restore"
tar -xzf "$ARCH" -C "$SB/restore" 2>/dev/null
expect "restored src1 is identical to the original" diff -r "$D/src1" "$SB/restore/${D#/}/src1"
expect "restored src2 is identical to the original" diff -r "$D/src2" "$SB/restore/${D#/}/src2"

section "T05 Relative BACKUP_DIR is resolved to an absolute path"
new_sandbox
setconf "$(q "$D/src1")" "../rel_out"
run
expect "exit code is 0"                         rc_is 0
expect "log shows an absolute backup directory" contains "Backup directory: $WORK/rel_out"


# =====================================================================
# 2. CONFIG VALIDATION
# =====================================================================

section "T06 Missing configuration file"
new_sandbox
run
expect "exit code is 1"                         rc_is 1
expect "error message mentions the config file" contains "Configuration file not found"

section "T07 SOURCE_DIRS not defined"
new_sandbox
echo "BACKUP_DIR=\"$OUTDIR\"" > "$SB/Archon_Configs/Archon.conf"
run
expect "exit code is 1"                         rc_is 1
expect "error message mentions SOURCE_DIRS"     contains "SOURCE_DIRS is not defined"

section "T08 SOURCE_DIRS is empty"
new_sandbox
printf 'SOURCE_DIRS=()\nBACKUP_DIR="%s"\n' "$OUTDIR" > "$SB/Archon_Configs/Archon.conf"
run
expect "exit code is 1"                         rc_is 1
expect "error message says no sources"          contains "No source directories configured"

section "T09 BACKUP_DIR not defined"
new_sandbox
echo "SOURCE_DIRS=(\"$D/src1\")" > "$SB/Archon_Configs/Archon.conf"
run
expect "exit code is non-zero"                  rc_not_zero
expect "error message mentions BACKUP_DIR"      contains "BACKUP_DIR is not defined"


# =====================================================================
# 3. SAFETY CHECKS
# =====================================================================

section "T10 Nonexistent source directory"
new_sandbox
setconf "$(q "$D/does_not_exist")" "$OUTDIR"
run
expect "exit code is 1"                         rc_is 1
expect "error says source not found"            contains "Source directory not found"
expect "no archive was created"                 file_missing "$OUTDIR"

section "T11 Backing up / is refused"
new_sandbox
setconf "$(q "/")" "$OUTDIR"
RUN_TIMEOUT=10
TIMEOUT_CMD=(timeout 10)
run
expect "exit code is 1"                         rc_is 1
expect "error says root is not supported"       contains "root directory is not supported"
expect "no archive was created"                 file_missing "$OUTDIR"

new_sandbox
setconf "$(q "/tmp/..")" "$OUTDIR"
run
expect "'/tmp/..' (resolves to /) is refused too" contains "root directory is not supported"
if command -v timeout >/dev/null 2>&1; then
	TIMEOUT_CMD=(timeout "${RUN_TIMEOUT:-60}")
fi
RUN_TIMEOUT=60

section "T12 Backup directory inside a source directory"
new_sandbox
setconf "$(q "$D/src1")" "$D/src1/backups"
run
expect "exit code is 1"                         rc_is 1
expect "error says backup dir is inside source" contains "inside a source directory"

new_sandbox
setconf "$(q "$D/src1")" "$D/src1"
run
expect "backup dir equal to source is refused"  contains "inside a source directory"


# =====================================================================
# 4. VERIFY STEP
# =====================================================================

section "T13 Verification catches a corrupted archive"
new_sandbox
setconf "$(q "$D/src1")" "$OUTDIR"
sed 's|^[[:space:]]*tar -czf.*|echo garbage > "$BACKUP_FILE"|' "$SB/Archon.sh" > "$SB/Archon.patched"
if cmp -s "$SB/Archon.sh" "$SB/Archon.patched"; then
	skip "could not patch the tar line (script layout changed)"
else
	mv "$SB/Archon.patched" "$SB/Archon.sh"
	run
	expect "exit code is 1"                     rc_is 1
	expect "error says verification failed"     contains "verification failed"
fi

section "T14 Verification catches an empty archive"
new_sandbox
setconf "$(q "$D/src1")" "$OUTDIR"
sed 's|^[[:space:]]*tar -czf.*|: > "$BACKUP_FILE"|' "$SB/Archon.sh" > "$SB/Archon.patched"
if cmp -s "$SB/Archon.sh" "$SB/Archon.patched"; then
	skip "could not patch the tar line (script layout changed)"
else
	mv "$SB/Archon.patched" "$SB/Archon.sh"
	run
	expect "exit code is 1"                     rc_is 1
	expect "error says archive is empty"        contains "missing or empty"
fi

section "T15 tar failure (unreadable file) stops the script"
new_sandbox
if [[ $EUID -eq 0 ]]; then
	skip "root can read any file, test needs a normal user"
else
	echo "secret" > "$D/src1/locked.txt"
	chmod 000 "$D/src1/locked.txt"
	setconf "$(q "$D/src1")" "$OUTDIR"
	run
	expect "exit code is non-zero"              rc_not_zero
	expect "success message is NOT printed"     not_contains "Backup archive created"
fi


# =====================================================================
# 5. LOGGING AND COLORS
# =====================================================================

section "T16 Logs are written to Archon_Logs (auto-created)"
new_sandbox
setconf "$(q "$D/src1")" "$OUTDIR"
expect "Archon_Logs does not exist before the run" file_missing "$SB/Archon_Logs"
run
expect "Archon_Logs was created"                dir_exists "$SB/Archon_Logs"
expect "today's log file exists"                file_exists "$(today_log)"
expect "log lines have timestamp and level"     log_has_ts "$(today_log)"
expect "log contains the success line"          log_has "$(today_log)" "Backup completed successfully"

section "T17 Log file is appended, not overwritten"
new_sandbox
setconf "$(q "$D/src1")" "$OUTDIR"
run
before="$(wc -l < "$(today_log)")"
run
after="$(wc -l < "$(today_log)")"
expect "line count grows after a second run ($before -> $after)" [ "$after" -gt "$before" ]

section "T18 Errors are written to the log file"
new_sandbox
setconf "$(q "$D/does_not_exist")" "$OUTDIR"
run
expect "log contains an [ERROR] line"           log_has "$(today_log)" "[ERROR]"
expect "log contains the error message"         log_has "$(today_log)" "Source directory not found"

section "T19 Colors: terminal vs pipe vs NO_COLOR"
new_sandbox
setconf "$(q "$D/src1")" "$OUTDIR"
run
expect "piped output has no color codes"        no_escape
if can_script; then
	new_sandbox
	setconf "$(q "$D/src1")" "$OUTDIR"
	run_tty
	expect "terminal output has color codes"    has_escape
	expect "log file has no color codes (after a colored run)" log_no_esc "$(today_log)"

	new_sandbox
	setconf "$(q "$D/src1")" "$OUTDIR"
	run_tty NO_COLOR=1
	expect "NO_COLOR=1 disables colors on a terminal" no_escape
else
	skip "'script' command not available, terminal color tests skipped"
fi


# =====================================================================
# 6. SUDO OWNERSHIP AND LOG FALLBACK
# =====================================================================

section "T20 Ownership is returned to the invoking user (sudo)"
new_sandbox
setconf "$(q "$D/src1")" "$SB/owned_out"
if [[ $EUID -eq 0 ]]; then
	TARGET_USER="${SUDO_USER:-nobody}"
	if id "$TARGET_USER" >/dev/null 2>&1; then
		run SUDO_USER="$TARGET_USER"
		find_arch "$SB/owned_out"
		expect "exit code is 0"                 rc_is 0
		expect "Archon_Logs owned by $TARGET_USER" owner_is "$SB/Archon_Logs" "$TARGET_USER"
		expect "log file owned by $TARGET_USER" owner_is "$(today_log)" "$TARGET_USER"
		expect "new backup dir owned by $TARGET_USER" owner_is "$SB/owned_out" "$TARGET_USER"
		expect "archive owned by $TARGET_USER"  owner_is "$ARCH" "$TARGET_USER"
	else
		skip "user '$TARGET_USER' does not exist"
	fi
elif sudo -n true 2>/dev/null; then
	OUT="$(cd "$SB" && sudo -n env TMPDIR="$SB/tmp" bash ./Archon.sh 2>"$SB/stderr.txt")"
	RC=$?
	ERR="$(<"$SB/stderr.txt")"
	ALL="$OUT"$'\n'"$ERR"
	find_arch "$SB/owned_out"
	ME="$(id -un)"
	expect "exit code is 0"                     rc_is 0
	expect "Archon_Logs owned by $ME"           owner_is "$SB/Archon_Logs" "$ME"
	expect "log file owned by $ME"              owner_is "$(today_log)" "$ME"
	expect "archive owned by $ME"               owner_is "$ARCH" "$ME"
else
	skip "needs root or passwordless sudo (try: sudo ./tests/run_tests.sh)"
fi

section "T21 Log fallback to temp directory when Archon_Logs is not writable"
new_sandbox
if [[ $EUID -eq 0 ]]; then
	skip "root can write anywhere, test needs a normal user"
else
	mkdir -p "$SB/Archon_Logs"
	chmod 555 "$SB/Archon_Logs"
	setconf "$(q "$D/src1")" "$OUTDIR"
	run
	find_arch "$OUTDIR"
	expect "exit code is 0 (backup still works)" rc_is 0
	expect "warning about fallback is shown"    contains "Logging to"
	expect "fallback log file was created"      file_exists "$SB/tmp/Archon_Logs_$(id -u)/archon_$(date +%Y-%m-%d).log"
	expect "archive was still created"          file_exists "$ARCH"
fi


# =====================================================================
# 7. PREFIX, DATE FORMAT AND RETENTION (1.3.0 / 1.4.0)
# =====================================================================

section "T22 Custom BACKUP_PREFIX and DATE_FORMAT"
custom_name_ok() { [[ "$(basename "$ARCH")" =~ ^docs_[0-9]{8}\.tar\.gz$ ]]; }

new_sandbox
setconf "$(q "$D/src1")" "$OUTDIR"
printf 'BACKUP_PREFIX="docs"\nDATE_FORMAT="%%Y%%m%%d"\n' >> "$SB/Archon_Configs/Archon.conf"
run
find_arch "$OUTDIR" docs
expect "exit code is 0"                          rc_is 0
expect "archive is named docs_YYYYMMDD.tar.gz"   custom_name_ok

new_sandbox
setconf "$(q "$D/src1")" "$OUTDIR"
printf 'BACKUP_PREFIX=""\nDATE_FORMAT=""\n' >> "$SB/Archon_Configs/Archon.conf"
run
find_arch "$OUTDIR"
expect "empty values fall back to the defaults"  name_ok

new_sandbox
setconf "$(q "$D/src1")" "$OUTDIR"
echo 'BACKUP_PREFIX="../evil"' >> "$SB/Archon_Configs/Archon.conf"
run
expect "prefix with ../ is rejected (exit 1)"    rc_is 1
expect "error mentions BACKUP_PREFIX"            contains "BACKUP_PREFIX"
expect "nothing was created in BACKUP_DIR"       file_missing "$OUTDIR"

new_sandbox
setconf "$(q "$D/src1")" "$OUTDIR"
echo 'BACKUP_PREFIX="my docs"' >> "$SB/Archon_Configs/Archon.conf"
run
expect "prefix with a space is rejected (exit 1)" rc_is 1

new_sandbox
setconf "$(q "$D/src1")" "$OUTDIR"
echo 'DATE_FORMAT="%Y/%m"' >> "$SB/Archon_Configs/Archon.conf"
run
expect "date format producing '/' is rejected"   rc_is 1
expect "error mentions DATE_FORMAT"              contains "DATE_FORMAT"

new_sandbox
setconf "$(q "$D/src1")" "$OUTDIR"
echo 'DATE_FORMAT="%Y %m"' >> "$SB/Archon_Configs/Archon.conf"
run
expect "date format producing a space is rejected" rc_is 1

section "T23 Retention: KEEP_LAST keeps the newest archives"
new_sandbox
mkdir -p "$OUTDIR/sub"
for i in 1 2 3 4 5; do touch -d "2026-01-0$i" "$OUTDIR/backup_old$i.tar.gz"; done
echo x > "$OUTDIR/backup_has space.tar.gz"
touch -d "2026-01-06" "$OUTDIR/backup_has space.tar.gz"
echo x > "$OUTDIR/docs_keep.tar.gz"
echo x > "$OUTDIR/notes.txt"
echo x > "$OUTDIR/sub/backup_nested.tar.gz"
setconf "$(q "$D/src1")" "$OUTDIR"
echo 'KEEP_LAST=3' >> "$SB/Archon_Configs/Archon.conf"
run
find_arch "$OUTDIR"
expect "exit code is 0"                          rc_is 0
expect "the new archive is kept"                 file_exists "$ARCH"
expect "newest old archive is kept (has space)"  file_exists "$OUTDIR/backup_has space.tar.gz"
expect "second newest old archive is kept (old5)" file_exists "$OUTDIR/backup_old5.tar.gz"
expect "older archive removed (old4)"            file_missing "$OUTDIR/backup_old4.tar.gz"
expect "older archive removed (old3)"            file_missing "$OUTDIR/backup_old3.tar.gz"
expect "older archive removed (old1)"            file_missing "$OUTDIR/backup_old1.tar.gz"
expect "archive with another prefix is untouched" file_exists "$OUTDIR/docs_keep.tar.gz"
expect "non-archive file is untouched"           file_exists "$OUTDIR/notes.txt"
expect "archive in a subdirectory is untouched"  file_exists "$OUTDIR/sub/backup_nested.tar.gz"
expect "removals are written to the log"         log_has "$(today_log)" "Removed old backup"

section "T24 Retention is off by default"
new_sandbox
mkdir -p "$OUTDIR"
touch -d "2026-01-01" "$OUTDIR/backup_old1.tar.gz"
setconf "$(q "$D/src1")" "$OUTDIR"
run
expect "KEEP_LAST not set: nothing is removed"   file_exists "$OUTDIR/backup_old1.tar.gz"

new_sandbox
mkdir -p "$OUTDIR"
touch -d "2026-01-01" "$OUTDIR/backup_old1.tar.gz"
setconf "$(q "$D/src1")" "$OUTDIR"
echo 'KEEP_LAST=0' >> "$SB/Archon_Configs/Archon.conf"
run
expect "KEEP_LAST=0: nothing is removed"         file_exists "$OUTDIR/backup_old1.tar.gz"

section "T25 KEEP_LAST validation"
new_sandbox
setconf "$(q "$D/src1")" "$OUTDIR"
echo 'KEEP_LAST=abc' >> "$SB/Archon_Configs/Archon.conf"
run
expect "KEEP_LAST=abc is rejected (exit 1)"      rc_is 1
expect "error mentions KEEP_LAST"                contains "KEEP_LAST"
expect "no backup was made"                      file_missing "$OUTDIR"

new_sandbox
setconf "$(q "$D/src1")" "$OUTDIR"
echo 'KEEP_LAST=-1' >> "$SB/Archon_Configs/Archon.conf"
run
expect "KEEP_LAST=-1 is rejected (exit 1)"       rc_is 1

new_sandbox
mkdir -p "$OUTDIR"
touch -d "2026-01-01" "$OUTDIR/backup_old1.tar.gz"
setconf "$(q "$D/src1")" "$OUTDIR"
echo 'KEEP_LAST=08' >> "$SB/Archon_Configs/Archon.conf"
run
expect "KEEP_LAST=08 is accepted as 8 (no octal error)" rc_is 0
expect "archive kept because 8 > number of archives"    file_exists "$OUTDIR/backup_old1.tar.gz"

section "T26 Retention does not run when the backup fails"
new_sandbox
mkdir -p "$OUTDIR"
touch -d "2026-01-01" "$OUTDIR/backup_old1.tar.gz"
touch -d "2026-01-02" "$OUTDIR/backup_old2.tar.gz"
setconf "$(q "$D/src1")" "$OUTDIR"
echo 'KEEP_LAST=1' >> "$SB/Archon_Configs/Archon.conf"
sed 's|^[[:space:]]*tar -czf.*|echo garbage > "$BACKUP_FILE"|' "$SB/Archon.sh" > "$SB/Archon.patched"
if cmp -s "$SB/Archon.sh" "$SB/Archon.patched"; then
	skip "could not patch the tar line (script layout changed)"
else
	mv "$SB/Archon.patched" "$SB/Archon.sh"
	run
	expect "backup failed (exit 1)"              rc_is 1
	expect "old archive 1 is still there"        file_exists "$OUTDIR/backup_old1.tar.gz"
	expect "old archive 2 is still there"        file_exists "$OUTDIR/backup_old2.tar.gz"
fi


# =====================================================================
# 8. STATIC CHECKS
# =====================================================================

section "T27 Static checks"
expect "bash -n (syntax) passes"                bash -n "$SCRIPT_UNDER_TEST"
if LC_ALL=C grep -q '[^[:print:][:space:]]' "$SCRIPT_UNDER_TEST"; then
	fail "script contains non-ASCII / hidden characters"
	LC_ALL=C grep -n '[^[:print:][:space:]]' "$SCRIPT_UNDER_TEST" | sed 's/^/        line /'
else
	pass "script contains only plain ASCII characters"
fi
expect "version header looks like '# Version: X.Y.Z'" grep -qE '^# Version: [0-9]+\.[0-9]+\.[0-9]+$' "$SCRIPT_UNDER_TEST"
expect "script starts with a bash shebang"      grep -q '^#!/bin/bash' "$SCRIPT_UNDER_TEST"
expect "strict mode (set -Eeuo pipefail) is on" grep -q '^set -Eeuo pipefail' "$SCRIPT_UNDER_TEST"
if command -v shellcheck >/dev/null 2>&1; then
	expect "shellcheck reports no warnings"     shellcheck -S warning -e SC1090,SC1091 "$SCRIPT_UNDER_TEST"
else
	skip "shellcheck not installed (sudo apt install shellcheck)"
fi


# =====================================================================
# SUMMARY
# =====================================================================

TOTAL=$((PASS + FAIL + SKIP))
echo
echo "======================================="
echo "${BOLD}Summary${RESET}: $TOTAL checks, ${GREEN}$PASS passed${RESET}, ${RED}$FAIL failed${RESET}, ${YELLOW}$SKIP skipped${RESET}"

if [[ $FAIL -gt 0 ]]; then
	echo
	echo "${RED}Failed checks:${RESET}"
	for item in "${FAILED[@]}"; do
		echo "  - $item"
	done
	exit 1
fi

echo "${GREEN}All checks passed.${RESET}"
exit 0
