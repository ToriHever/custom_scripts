-- Создание таблицы для хранения задач Jira
DROP TABLE IF EXISTS jira_issues CASCADE;
DROP TABLE IF EXISTS jira_issue_links CASCADE;

CREATE TABLE jira_issues (
    id SERIAL PRIMARY KEY,
    issue_key VARCHAR(50) UNIQUE NOT NULL,
    issue_type VARCHAR(100),
    status VARCHAR(100),
    created_date TIMESTAMP,
    time_original_estimate NUMERIC(10, 2), -- в часах
    time_spent NUMERIC(10, 2), -- в часах
    updated_date TIMESTAMP,
    sprint VARCHAR(500),
    epic_link VARCHAR(50),
    summary TEXT,
    assignee VARCHAR(255),
    reporter VARCHAR(255),
    priority VARCHAR(50),
    labels TEXT[], -- массив меток
    linked_issues TEXT[], -- массив ключей связанных задач для быстрого доступа
    last_synced TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Таблица для детальных связей между задачами (для построения карты связей)
CREATE TABLE jira_issue_links (
    id SERIAL PRIMARY KEY,
    source_issue_key VARCHAR(50) NOT NULL,
    target_issue_key VARCHAR(50) NOT NULL,
    link_type VARCHAR(100),
    link_type_name VARCHAR(200),
    direction VARCHAR(20), -- 'inward' или 'outward'
    direction_label VARCHAR(100), -- например: "разделить от", "разделить на"
    target_summary TEXT,
    target_status VARCHAR(100),
    target_priority VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (source_issue_key) REFERENCES jira_issues(issue_key) ON DELETE CASCADE
);

-- Индексы для основной таблицы
CREATE INDEX idx_issue_key ON jira_issues(issue_key);
CREATE INDEX idx_created_date ON jira_issues(created_date);
CREATE INDEX idx_status ON jira_issues(status);
CREATE INDEX idx_assignee ON jira_issues(assignee);
CREATE INDEX idx_sprint ON jira_issues(sprint);
CREATE INDEX idx_epic_link ON jira_issues(epic_link);

-- Индексы для таблицы связей (для построения графа)
CREATE INDEX idx_source_issue ON jira_issue_links(source_issue_key);
CREATE INDEX idx_target_issue ON jira_issue_links(target_issue_key);
CREATE INDEX idx_link_type ON jira_issue_links(link_type);
CREATE INDEX idx_both_issues ON jira_issue_links(source_issue_key, target_issue_key);

-- Комментарий к таблице
COMMENT ON TABLE jira_issues IS 'Таблица для хранения задач из Jira';
COMMENT ON COLUMN jira_issues.time_original_estimate IS 'Первоначальная оценка в часах';
COMMENT ON COLUMN jira_issues.time_spent IS 'Затраченное время в часах';
COMMENT ON COLUMN jira_issues.linked_issues IS 'Массив ключей связанных задач (например: {PRMR-6924, PRMR-6925})';

COMMENT ON TABLE jira_issue_links IS 'Детальная информация о связях между задачами для построения карты связей';
COMMENT ON COLUMN jira_issue_links.direction IS 'Направление связи: inward (входящая) или outward (исходящая)';
COMMENT ON COLUMN jira_issue_links.direction_label IS 'Текстовое описание связи (например: "блокирует", "заблокирована")';