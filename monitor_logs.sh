#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="${LOG_DIR:-/LOGS}"
THRESHOLD="${THRESHOLD:-90}"
MIN_AGE_MINUTES="${MIN_AGE_MINUTES:-1}"
LOCK_FILE="${LOCK_FILE:-/run/lock/akos-monitor.lock}"
SERVICES=(auth_service data_process_service system_event_handler_service)

exec 9>"$LOCK_FILE"
flock -n 9 || { echo "Мониторинг уже запущен"; exit 1; }

if ! mountpoint -q "$LOG_DIR"; then
  echo "Ошибка: $LOG_DIR не является точкой монтирования" >&2
  exit 1
fi

read -r total used available usage < <(df -P -B1 "$LOG_DIR" | awk 'NR==2 {gsub(/%/, "", $5); print $2,$3,$4,$5}')
quota=$((total / 3))
echo "Заполненность: ${usage}% (порог: ${THRESHOLD}%)"
echo "Квота каждого сервиса: $quota байт"

if (( usage <= THRESHOLD )); then
  echo "Порог не превышен. Архивация не нужна."
  exit 0
fi

processed=0
for service in "${SERVICES[@]}"; do
  dir="$LOG_DIR/$service"
  if [[ ! -d "$dir" ]]; then
    echo "Пропущен отсутствующий каталог: $dir"
    continue
  fi
  size=$(du -s -B1 "$dir" | awk '{print $1}')
  if (( size <= quota )); then
    echo "$service: квота не превышена"
    continue
  fi

  # Find gives paths relative to the service directory. Do not archive current/recent files.
  mapfile -d '' files < <(cd "$dir" && find . -maxdepth 1 -type f -name '*.log' -mmin +"$MIN_AGE_MINUTES" -printf '%f\0' | sort -z)
  if (( ${#files[@]} == 0 )); then
    echo "$service: квота превышена, но старых логов нет"
    continue
  fi

  archive="$dir/archive_$(date +%Y%m%d_%H%M%S_%N).tar.gz"
  # A failed archive must never cause deletion of originals.
  if ! (cd "$dir" && printf '%s\0' "${files[@]}" | tar --null -T - -czf "$archive"); then
    rm -f -- "$archive"
    echo "Ошибка архивации: $service" >&2
    exit 1
  fi
  if ! tar -tzf "$archive" >/dev/null; then
    rm -f -- "$archive"
    echo "Ошибка проверки архива: $service" >&2
    exit 1
  fi
  # Only the selected candidate files are removed, and only after validation.
  (cd "$dir" && rm -- "${files[@]}")
  echo "$service: архив создан $(basename "$archive"), удалено файлов: ${#files[@]}"
  processed=$((processed+1))
done
if (( processed == 0 )); then
  echo "Архивация не выполнена: нет каталогов с подходящими старыми логами"
fi
echo "Мониторинг завершён"
