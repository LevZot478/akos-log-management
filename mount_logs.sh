#!/bin/bash

set -euo pipefail

UUID="6834094c-5588-4558-acff-f0d17d0e42a2"
MOUNT_POINT="/LOGS"

# Проверяем наличие нужного раздела
if ! blkid -U "$UUID" >/dev/null 2>&1; then
    echo "Ошибка: раздел с UUID=$UUID не найден"
    exit 1
fi

# Создаём точку монтирования
mkdir -p "$MOUNT_POINT"

# Не допускаем подключения другого устройства
if mountpoint -q "$MOUNT_POINT"; then
    current_uuid=$(findmnt -n -o UUID --target "$MOUNT_POINT")

    if [[ "$current_uuid" == "$UUID" ]]; then
        echo "/LOGS уже смонтирован с нужного раздела"
        exit 0
    fi

    echo "Ошибка: /LOGS занят другой файловой системой"
    exit 1
fi

# Подключаем раздел
mount "UUID=$UUID" "$MOUNT_POINT"
echo "Раздел успешно смонтирован в /LOGS"
