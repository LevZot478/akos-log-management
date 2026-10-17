# АКОС — управление логами в Linux

Лабораторная работа: хранение журналов трёх сервисов на отдельном разделе, автоматическое монтирование при старте среды, контроль заполнения и архивация старых `.log` в `.tar.gz`.

## Функциональность

- Дополнительный виртуальный диск VHDX (1 GiB), GPT-раздел и файловая система ext4.
- Монтирование раздела по UUID в `/LOGS` через Bash и systemd.
- Три каталога: `auth_service`, `data_process_service`, `system_event_handler_service`.
- При заполнении раздела **строго более 90%** скрипт проверяет квоту каждой папки (`ёмкость / 3`). Архивирует старые `.log` только в каталогах, превысивших квоту.
- Архивы `.tar.gz` проверяются перед удалением исходников; одновременные запуски блокируются `flock`.
- Проверка выполняется по таймеру systemd, предусмотрено 5 автоматических тестов.

## Структура

```text
akos-log-management/
├── mount_logs.sh                 # Монтирование раздела по UUID
├── monitor_logs.sh               # Проверка заполнения и архивация
├── test_monitor.sh               # Пять автоматических тестов
├── systemd/
│   ├── mount-logs.service
│   ├── monitor-logs.service
│   └── monitor-logs.timer
├── windows/start-akos.ps1        # Подключение VHDX в WSL 2
├── docs/DEFENSE.md               # Пояснение и вопросы к защите
├── .gitignore
└── README.md
```

## Окружение и подготовка

Использовались Windows + WSL 2 + Ubuntu с включённым systemd. В Windows создан VHDX (1 GiB), подключённый к WSL через `wsl --mount ... --vhd --bare`; на диске создан GPT-раздел и ext4. **Не запускайте `fdisk` или `mkfs` на уже используемых дисках**: это может уничтожить данные.

В этой конкретной установке UUID файловой системы: `6834094c-5588-4558-acff-f0d17d0e42a2`. Перед использованием на другом компьютере нужно заменить UUID в `mount_logs.sh` и `windows/start-akos.ps1` по результату `sudo blkid`, а также пути `/home/lev/akos-lab/` и имя Ubuntu в файлах конфигурации. VHDX не включён в репозиторий.

## Установка в Ubuntu

```bash
mkdir -p ~/akos-lab
cp mount_logs.sh monitor_logs.sh test_monitor.sh ~/akos-lab/
chmod +x ~/akos-lab/*.sh
sudo mkdir -p /LOGS
sudo cp systemd/*.service systemd/*.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable mount-logs.service
sudo systemctl enable --now monitor-logs.timer
```

**Внимание:** прежде чем включать службу, VHDX должен быть уже присоединён к WSL. Скрипт `mount_logs.sh` не создаёт диск и не форматирует раздел, а подключает **существующую** ext4 по UUID. Для ручной проверки:

```bash
sudo ~/akos-lab/mount_logs.sh
df -hT /LOGS
systemctl status mount-logs.service --no-pager
```

Для автоматического подключения VHDX со стороны Windows используется `windows/start-akos.ps1`, выполняемый в PowerShell с повышенными правами или Планировщиком задач **от учётной записи владельца Ubuntu**, с опцией «Выполнять с наивысшими правами» и триггером «При входе пользователя». В рабочей конфигурации файл размещается в `%USERPROFILE%\akos-disks\start-akos.ps1`. Факт запуска по этому триггеру следует отдельно проверить после нового входа в Windows; ручной запуск задания не доказывает работу триггера.

## Ручная проверка

```bash
sudo systemctl start monitor-logs.service
sudo systemctl show monitor-logs.service -p Result -p ExecMainStatus
sudo journalctl -u monitor-logs.service -n 25 --no-pager
systemctl list-timers --all | grep monitor-logs
```

Ожидаем `Result=success`, `ExecMainStatus=0`. Служба `oneshot` может иметь статус `inactive (dead)` после нормального завершения. Таймер должен быть `active (waiting)`.

## Автоматические тесты

```bash
sudo bash ~/akos-lab/test_monitor.sh
```

Тесты создают временный файл-образ ext4 и монтируют его через loop, **не используют рабочий `/LOGS`**. Проверяются: отсутствие архивации ниже порога; превышение квоты одним сервисом; двумя сервисами; сохранность новых логов; ошибка при отсутствии монтирования. При успехе выводится `ALL TESTS PASSED`.

## Ограничения реализации

- «Старые» файлы определяются по времени последнего изменения (`find -mmin`), а не по Unix timestamp в имени. Имена `.log` должны соответствовать формату из задания, но поле timestamp скриптом не разбирается.
- Архивирование активного лога полностью не исключено: критерий возраста является упрощением. Для промышленного использования нужна согласованная ротация/переоткрытие файла сервисом.
- Сжатие не гарантирует освобождение места до 90%; при уже полностью заполненном диске на создание архива может не хватить пространства.
- Если весь раздел превышает 90%, но ни один каталог не превышает свою треть, скрипт ничего не удаляет (в соответствии с ограничением на выбор каталогов).
- Присоединение VHDX выполняется на стороне Windows. `systemd` может смонтировать UUID только после появления раздела в WSL.

## Подтверждённые проверки

На учебной системе: `df -hT /LOGS` показывал ext4 на `/dev/sde1`; `mount-logs.service` и `monitor-logs.timer` — `active`; `monitor-logs.service` — `Result=success`, `ExecMainStatus=0`; пять автоматических тестов завершились `ALL TESTS PASSED`; Планировщик Windows при ручном запуске задания сообщил `LastTaskResult=0`. Автоматический запуск непосредственно после повторного входа в Windows требует отдельного подтверждения.
