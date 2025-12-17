# Jira to PostgreSQL Sync

Скрипт для синхронизации задач из Jira в PostgreSQL базу данных.

## Установка

1. Установите зависимости:
```bash
pip install -r requirements.txt
```

2. Создайте файл `.env` на основе `.env.example`:
```bash
cp .env.example .env
```

3. Заполните `.env` вашими данными:
```env
# Jira настройки
JIRA_URL=https://jira.ddos-guard.net
JIRA_LOGIN=v.miroshnikova
JIRA_PASSWORD=your_password

# Настройки PostgreSQL
PGHOST=your_host
PGUSER=tori_db
PGPASSWORD=your_password
PGDATABASE=mar_db
PGPORT=5432
```

## Использование

### Базовый запуск

```bash
source venv/Scripts/activate (. venv/Scripts/activate)

python jira_sync.py
```

По умолчанию используется JQL: `assignee=currentUser() AND created >= 2025-10-01 AND created <= 2025-12-16`

### Запуск с кастомным JQL

```bash
python jira_sync.py "project=PRMR AND status='В работе'"
```

### Примеры JQL запросов

```bash
# Все ваши задачи за последний месяц
python jira_sync.py "assignee=currentUser() AND created >= startOfMonth()"

# Все задачи проекта PRMR
python jira_sync.py "project=PRMR"

# Задачи в работе
python jira_sync.py "status='В работе' AND assignee=currentUser()"

# Задачи с меткой SEO
python jira_sync.py "labels=SEO"
```

## Структура БД

Скрипт создает две таблицы:

### 1. `jira_issues` - основная таблица задач

| Колонка | Тип | Описание |
|---------|-----|----------|
| id | SERIAL | Внутренний ID (первичный ключ) |
| issue_key | VARCHAR(50) | Код задачи (например, PRMR-6929) |
| issue_type | VARCHAR(100) | Тип задачи (Задача, История и т.д.) |
| status | VARCHAR(100) | Статус задачи |
| created_date | TIMESTAMP | Дата создания |
| time_original_estimate | NUMERIC(10,2) | Первоначальная оценка (в часах) |
| time_spent | NUMERIC(10,2) | Затраченное время (в часах) |
| updated_date | TIMESTAMP | Дата обновления |
| sprint | VARCHAR(500) | Название спринта |
| epic_link | VARCHAR(50) | Ссылка на эпик |
| summary | TEXT | Описание задачи |
| assignee | VARCHAR(255) | Исполнитель |
| reporter | VARCHAR(255) | Репортер |
| priority | VARCHAR(50) | Приоритет |
| labels | TEXT[] | Метки (массив) |
| **linked_issues** | **TEXT[]** | **Массив ключей связанных задач** |
| last_synced | TIMESTAMP | Время последней синхронизации |

### 2. `jira_issue_links` - детальная таблица связей для построения карты

| Колонка | Тип | Описание |
|---------|-----|----------|
| id | SERIAL | Внутренний ID |
| source_issue_key | VARCHAR(50) | Исходная задача |
| target_issue_key | VARCHAR(50) | Связанная задача |
| link_type | VARCHAR(100) | ID типа связи |
| link_type_name | VARCHAR(200) | Название типа связи |
| direction | VARCHAR(20) | Направление (inward/outward) |
| direction_label | VARCHAR(100) | Описание связи ("блокирует", "разделить на") |
| target_summary | TEXT | Описание связанной задачи |
| target_status | VARCHAR(100) | Статус связанной задачи |
| target_priority | VARCHAR(50) | Приоритет связанной задачи |
| created_at | TIMESTAMP | Время создания записи |

## Полезные JQL запросы

```bash
# 1. По меткам и конкретному пользователю
python jira_sync.py "labels=SEO AND assignee=v.miroshnikova"

# 2. По меткам и текущему пользователю
python jira_sync.py "labels=SEO AND assignee=currentUser()"

# 3. По меткам, пользователю и периоду
python jira_sync.py "labels=SEO AND assignee=currentUser() AND created >= 2025-10-01"

# 4. По нескольким меткам
python jira_sync.py "labels IN (SEO, Дзен) AND assignee=currentUser()"

# 5. По меткам и проекту
python jira_sync.py "labels=SEO AND project=PRMR AND assignee=currentUser()"

# 6. По меткам, пользователю и статусу
python jira_sync.py "labels=SEO AND assignee=currentUser() AND status='В работе'"
```
### Полезные операторы JQL:

```bash
# AND - оба условия должны выполняться
python jira_sync.py "A AND B"

# OR - хотя бы одно условие
python jira_sync.py "A OR B"

# IN - одно из значений списка
python jira_sync.py "status IN ('В работе', 'Открыто')"

# NOT - отрицание
python jira_sync.py "labels=SEO AND assignee!=v.miroshnikova"

# Комбинация со скобками
python jira_sync.py "(labels=SEO OR labels=Дзен) AND assignee=currentUser()"
```

## Полезные SQL запросы

### Основные запросы

```sql
-- Все задачи с временными метками (время уже в часах!)
SELECT 
    issue_key,
    issue_type,
    status,
    created_date,
    time_original_estimate as estimate_hours,
    time_spent as spent_hours,
    sprint,
    epic_link,
    array_length(linked_issues, 1) as links_count
FROM jira_issues
ORDER BY created_date DESC;

-- Задачи со связями
SELECT 
    issue_key,
    summary,
    linked_issues,
    array_length(linked_issues, 1) as connections_count
FROM jira_issues
WHERE linked_issues IS NOT NULL AND array_length(linked_issues, 1) > 0
ORDER BY array_length(linked_issues, 1) DESC;
```

### Работа со связями

```sql
-- Все связи конкретной задачи
SELECT 
    source_issue_key,
    direction_label,
    target_issue_key,
    target_summary,
    target_status,
    link_type_name
FROM jira_issue_links
WHERE source_issue_key = 'PRMR-6929';

-- Топ задач по количеству связей
SELECT 
    issue_key,
    summary,
    array_length(linked_issues, 1) as connections
FROM jira_issues
WHERE linked_issues IS NOT NULL
ORDER BY array_length(linked_issues, 1) DESC
LIMIT 10;

-- Граф связей для визуализации
SELECT 
    l.source_issue_key,
    i1.summary as source_summary,
    l.direction_label,
    l.target_issue_key,
    l.target_summary
FROM jira_issue_links l
JOIN jira_issues i1 ON l.source_issue_key = i1.issue_key;
```

### Статистика по спринтам

```sql
SELECT 
    sprint,
    COUNT(*) as tasks_count,
    ROUND(SUM(time_original_estimate) / 3600.0, 2) as total_estimate_hours,
    ROUND(SUM(time_spent) / 3600.0, 2) as total_spent_hours
FROM jira_issues
WHERE sprint IS NOT NULL
GROUP BY sprint
ORDER BY sprint DESC;
```

### Задачи по статусам

```sql
SELECT 
    status,
    COUNT(*) as count,
    ARRAY_AGG(issue_key ORDER BY created_date DESC) as issues
FROM jira_issues
GROUP BY status
ORDER BY count DESC;
```

### Задачи с метками

```sql
SELECT 
    issue_key,
    summary,
    labels
FROM jira_issues
WHERE 'SEO' = ANY(labels);
```

## Автоматизация

### Добавление в cron для ежедневной синхронизации

```bash
# Открыть crontab
crontab -e

# Добавить строку для запуска каждый день в 9:00
0 9 * * * cd /path/to/project && /usr/bin/python3 jira_sync.py >> /path/to/logs/jira_sync.log 2>&1
```

### Создание systemd сервиса

Создайте файл `/etc/systemd/system/jira-sync.service`:

```ini
[Unit]
Description=Jira Sync Service
After=network.target postgresql.service

[Service]
Type=oneshot
User=your_user
WorkingDirectory=/path/to/project
ExecStart=/usr/bin/python3 /path/to/project/jira_sync.py
Environment="PATH=/usr/bin:/usr/local/bin"

[Install]
WantedBy=multi-user.target
```

Создайте таймер `/etc/systemd/system/jira-sync.timer`:

```ini
[Unit]
Description=Run Jira Sync Daily

[Timer]
OnCalendar=daily
OnCalendar=09:00
Persistent=true

[Install]
WantedBy=timers.target
```

Активируйте:

```bash
sudo systemctl daemon-reload
sudo systemctl enable jira-sync.timer
sudo systemctl start jira-sync.timer
```

## Особенности

- **Две таблицы для связей**: 
  - `linked_issues` в основной таблице - для быстрого доступа к списку связанных задач
  - `jira_issue_links` - детальная информация о каждой связи для построения карты
- **Инкрементальная синхронизация**: При повторном запуске задачи обновляются (ON CONFLICT DO UPDATE)
- **Пагинация**: Автоматически обрабатывает большие объемы данных
- **Извлечение спринта**: Парсит название спринта из кастомного поля Jira
- **Время в часах**: Автоматически конвертирует секунды в часы с округлением до 2 знаков
- **Статистика**: После синхронизации выводится статистика по задачам и связям
- **Визуализация связей**: Детальная таблица связей позволяет строить карты зависимостей

## Решение проблем

### Ошибка подключения к Jira

Проверьте:
- Правильность URL (без слеша в конце)
- Логин и пароль
- Доступность Jira API

### Ошибка подключения к PostgreSQL

Проверьте:
- Хост и порт
- Имя пользователя и пароль
- Существование базы данных
- Права доступа пользователя

### Задачи не синхронизируются

Проверьте JQL запрос в Jira UI:
1. Откройте Jira
2. Перейдите в "Фильтры" → "Расширенный поиск"
3. Вставьте ваш JQL запрос
4. Убедитесь, что он возвращает результаты