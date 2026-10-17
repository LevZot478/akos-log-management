#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/monitor_logs.sh"
if (( EUID != 0 )); then
  echo "Запусти тесты: sudo bash $0" >&2
  exit 1
fi
command -v mkfs.ext4 >/dev/null || { echo 'Нужен mkfs.ext4'; exit 1; }
command -v flock >/dev/null || { echo 'Нужен flock'; exit 1; }

TMP=$(mktemp -d /tmp/akos-tests.XXXXXX)
MOUNT="$TMP/mounted"
IMAGE="$TMP/test.img"
mkdir -p "$MOUNT"
cleanup() {
  if mountpoint -q "$MOUNT"; then umount "$MOUNT"; fi
  rm -rf -- "$TMP"
}
trap cleanup EXIT
truncate -s 300M "$IMAGE"
mkfs.ext4 -q -F "$IMAGE"
mount -o loop "$IMAGE" "$MOUNT"
for s in auth_service data_process_service system_event_handler_service; do mkdir "$MOUNT/$s"; done

reset_data() {
  for s in auth_service data_process_service system_event_handler_service; do
    find "$MOUNT/$s" -maxdepth 1 -type f -delete
  done
}
make_log() {
  local service="$1" num="$2" size="$3" age="$4"
  local path="$MOUNT/$service/${service}_2026_10_${num}_1792000000.log"
  head -c "${size}M" /dev/zero > "$path"
  if [[ "$age" == old ]]; then touch -d '2 days ago' "$path"; fi
}
run_monitor() {
  LOG_DIR="$MOUNT" LOCK_FILE="$TMP/monitor.lock" bash "$SCRIPT" > "$TMP/output" 2>&1
}
check_over_90() {
  local pct
  pct=$(df -P "$MOUNT" | awk 'NR==2 {gsub(/%/,"",$5);print $5}')
  ((pct > 90)) || { echo "FAIL: заполнение только ${pct}%"; exit 1; }
}
check_archive() {
  local service="$1" count
  count=$(find "$MOUNT/$service" -maxdepth 1 -name 'archive_*.tar.gz' -type f | wc -l)
  ((count == 1)) || { echo "FAIL: неверное число архивов для $service: $count"; exit 1; }
  local a
  a=$(find "$MOUNT/$service" -maxdepth 1 -name 'archive_*.tar.gz' -print -quit)
  tar -tzf "$a" >/dev/null || { echo 'FAIL: архив повреждён'; exit 1; }
}
check_no_archive() {
  local service="$1"
  ! find "$MOUNT/$service" -maxdepth 1 -name 'archive_*.tar.gz' | grep -q . || { echo "FAIL: лишний архив в $service"; exit 1; }
}

# Test 1: below threshold
reset_data
make_log auth_service 11 1 old
run_monitor
check_no_archive auth_service
[[ -f "$MOUNT/auth_service/auth_service_2026_10_11_1792000000.log" ]]
echo 'PASS 1: порог не достигнут, архивирования нет'

# Test 2: one service exceeds quota
reset_data
make_log auth_service 12 110 old
make_log auth_service 13 110 old
check_over_90
run_monitor
check_archive auth_service
check_no_archive data_process_service
check_no_archive system_event_handler_service
[[ $(find "$MOUNT/auth_service" -maxdepth 1 -name '*.log' | wc -l) == 0 ]]
echo 'PASS 2: архивирован только auth_service'

# Test 3: two services exceed their quotas
reset_data
make_log auth_service 14 110 old
make_log data_process_service 15 110 old
check_over_90
run_monitor
check_archive auth_service
check_archive data_process_service
check_no_archive system_event_handler_service
echo 'PASS 3: архивированы два превышающих квоту сервиса'

# Test 4: new logs must remain untouched
reset_data
make_log auth_service 16 110 new
make_log auth_service 17 110 new
check_over_90
run_monitor
check_no_archive auth_service
[[ $(find "$MOUNT/auth_service" -maxdepth 1 -name '*.log' | wc -l) == 2 ]]
echo 'PASS 4: новые логи не удалены'

# Test 5: missing mount is rejected
if LOG_DIR="$TMP/absent" LOCK_FILE="$TMP/monitor.lock" bash "$SCRIPT" > "$TMP/output" 2>&1; then
  echo 'FAIL 5: принят несмонтированный путь'
  exit 1
fi
echo 'PASS 5: несмонтированный каталог отклонён'
echo 'ALL TESTS PASSED'
