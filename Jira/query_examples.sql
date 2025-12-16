-- ============================================================================
-- ПРИМЕРЫ SQL ЗАПРОСОВ ДЛЯ РАБОТЫ С ЗАДАЧАМИ И СВЯЗЯМИ JIRA
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. ОСНОВНЫЕ ЗАПРОСЫ К ЗАДАЧАМ
-- ----------------------------------------------------------------------------

-- Все задачи с их связями (массив)
SELECT 
    issue_key,
    summary,
    status,
    linked_issues,
    array_length(linked_issues, 1) as links_count
FROM jira_issues
WHERE linked_issues IS NOT NULL AND array_length(linked_issues, 1) > 0
ORDER BY array_length(linked_issues, 1) DESC;

-- Задачи без связей
SELECT issue_key, summary, status
FROM jira_issues
WHERE linked_issues IS NULL OR array_length(linked_issues, 1) = 0;

-- Поиск задачи, связанной с конкретной задачей
SELECT issue_key, summary, status
FROM jira_issues
WHERE 'PRMR-6924' = ANY(linked_issues);


-- ----------------------------------------------------------------------------
-- 2. РАБОТА С ДЕТАЛЬНОЙ ТАБЛИЦЕЙ СВЯЗЕЙ
-- ----------------------------------------------------------------------------

-- Все связи задачи (входящие и исходящие)
SELECT 
    l.source_issue_key,
    l.direction,
    l.direction_label,
    l.target_issue_key,
    l.target_summary,
    l.target_status,
    l.link_type_name
FROM jira_issue_links l
WHERE l.source_issue_key = 'PRMR-6929'
ORDER BY l.direction, l.target_issue_key;

-- Двусторонний просмотр связей (кто связан с задачей и с кем она связана)
SELECT 
    CASE 
        WHEN source_issue_key = 'PRMR-6929' THEN target_issue_key
        ELSE source_issue_key
    END as connected_issue,
    link_type_name,
    direction_label
FROM jira_issue_links
WHERE source_issue_key = 'PRMR-6929' OR target_issue_key = 'PRMR-6929';

-- Граф связей с деталями задач
SELECT 
    l.source_issue_key,
    i1.summary as source_summary,
    i1.status as source_status,
    l.direction_label,
    l.target_issue_key,
    l.target_summary,
    l.target_status,
    l.link_type_name
FROM jira_issue_links l
JOIN jira_issues i1 ON l.source_issue_key = i1.issue_key
ORDER BY l.source_issue_key, l.target_issue_key;


-- ----------------------------------------------------------------------------
-- 3. АНАЛИЗ СВЯЗЕЙ
-- ----------------------------------------------------------------------------

-- Топ задач по количеству связей
SELECT 
    issue_key,
    summary,
    status,
    array_length(linked_issues, 1) as connections_count
FROM jira_issues
WHERE linked_issues IS NOT NULL
ORDER BY array_length(linked_issues, 1) DESC
LIMIT 20;

-- Статистика по типам связей
SELECT 
    link_type_name,
    direction,
    direction_label,
    COUNT(*) as count
FROM jira_issue_links
GROUP BY link_type_name, direction, direction_label
ORDER BY count DESC;

-- Задачи, которые чаще всего блокируют другие
SELECT 
    source_issue_key,
    MAX(target_summary) as summary,
    COUNT(*) as blocks_count
FROM jira_issue_links
WHERE direction_label ILIKE '%блокир%'
GROUP BY source_issue_key
ORDER BY blocks_count DESC
LIMIT 10;


-- ----------------------------------------------------------------------------
-- 4. ГРАФ СВЯЗЕЙ ДЛЯ ВИЗУАЛИЗАЦИИ
-- ----------------------------------------------------------------------------

-- Данные для построения графа (nodes + edges)
-- Nodes (узлы)
SELECT 
    issue_key as id,
    summary as label,
    status,
    issue_type as type,
    priority
FROM jira_issues
WHERE issue_key IN (
    SELECT DISTINCT source_issue_key FROM jira_issue_links
    UNION
    SELECT DISTINCT target_issue_key FROM jira_issue_links
);

-- Edges (связи)
SELECT 
    source_issue_key as source,
    target_issue_key as target,
    link_type_name as label,
    direction_label as description,
    direction
FROM jira_issue_links;

-- Полный граф в одном запросе (для экспорта в JSON)
WITH nodes AS (
    SELECT 
        issue_key,
        summary,
        status,
        issue_type,
        priority
    FROM jira_issues
),
edges AS (
    SELECT 
        source_issue_key,
        target_issue_key,
        link_type_name,
        direction_label,
        direction
    FROM jira_issue_links
)
SELECT 
    json_build_object(
        'nodes', (SELECT json_agg(row_to_json(nodes)) FROM nodes),
        'edges', (SELECT json_agg(row_to_json(edges)) FROM edges)
    ) as graph_data;


-- ----------------------------------------------------------------------------
-- 5. ПОИСК ЦЕПОЧЕК И ЗАВИСИМОСТЕЙ
-- ----------------------------------------------------------------------------

-- Найти все задачи, связанные с эпиком (включая вложенные)
WITH RECURSIVE epic_tree AS (
    -- Начальная задача (эпик)
    SELECT 
        issue_key,
        summary,
        0 as level
    FROM jira_issues
    WHERE issue_key = 'PRMR-6924'
    
    UNION ALL
    
    -- Рекурсивно находим все связанные задачи
    SELECT 
        l.target_issue_key,
        i.summary,
        et.level + 1
    FROM epic_tree et
    JOIN jira_issue_links l ON et.issue_key = l.source_issue_key
    JOIN jira_issues i ON l.target_issue_key = i.issue_key
    WHERE et.level < 5  -- Ограничение глубины
)
SELECT 
    REPEAT('  ', level) || issue_key as hierarchy,
    summary,
    level
FROM epic_tree
ORDER BY level, issue_key;

-- Найти блокирующие цепочки
WITH RECURSIVE blocker_chain AS (
    SELECT 
        source_issue_key as issue,
        target_issue_key as blocker,
        direction_label,
        1 as depth,
        ARRAY[source_issue_key, target_issue_key] as chain
    FROM jira_issue_links
    WHERE direction_label ILIKE '%блокир%'
    
    UNION ALL
    
    SELECT 
        bc.issue,
        l.target_issue_key,
        l.direction_label,
        bc.depth + 1,
        bc.chain || l.target_issue_key
    FROM blocker_chain bc
    JOIN jira_issue_links l ON bc.blocker = l.source_issue_key
    WHERE l.direction_label ILIKE '%блокир%'
      AND bc.depth < 10
      AND NOT (l.target_issue_key = ANY(bc.chain))
)
SELECT 
    issue as blocked_issue,
    blocker as blocking_issue,
    depth as chain_length,
    array_to_string(chain, ' -> ') as full_chain
FROM blocker_chain
ORDER BY depth DESC, issue;


-- ----------------------------------------------------------------------------
-- 6. СТАТИСТИКА ПО ЗАДАЧАМ
-- ----------------------------------------------------------------------------

-- Задачи с оценкой времени и связями
SELECT 
    i.issue_key,
    i.summary,
    i.status,
    i.time_original_estimate as estimate_hours,
    i.time_spent as spent_hours,
    array_length(i.linked_issues, 1) as links_count,
    COUNT(l.id) as detailed_links_count
FROM jira_issues i
LEFT JOIN jira_issue_links l ON i.issue_key = l.source_issue_key
WHERE i.time_original_estimate IS NOT NULL
GROUP BY i.issue_key, i.summary, i.status, i.time_original_estimate, i.time_spent, i.linked_issues
ORDER BY i.time_original_estimate DESC;

-- Сводка по спринтам с учетом связей
SELECT 
    sprint,
    COUNT(*) as tasks_count,
    ROUND(SUM(time_original_estimate), 2) as total_estimate_hours,
    ROUND(AVG(time_original_estimate), 2) as avg_estimate_hours,
    COUNT(DISTINCT CASE WHEN array_length(linked_issues, 1) > 0 THEN issue_key END) as tasks_with_links
FROM jira_issues
WHERE sprint IS NOT NULL
GROUP BY sprint
ORDER BY sprint DESC;


-- ----------------------------------------------------------------------------
-- 7. ЭКСПОРТ ДЛЯ ВИЗУАЛИЗАЦИИ В РАЗНЫХ ФОРМАТАХ
-- ----------------------------------------------------------------------------

-- Для D3.js / Vis.js / Cytoscape.js
SELECT json_build_object(
    'nodes', json_agg(DISTINCT jsonb_build_object(
        'id', issue_key,
        'label', summary,
        'status', status,
        'type', issue_type,
        'priority', priority
    )),
    'links', (
        SELECT json_agg(jsonb_build_object(
            'source', source_issue_key,
            'target', target_issue_key,
            'type', link_type_name,
            'label', direction_label
        ))
        FROM jira_issue_links
    )
) as graph_json
FROM jira_issues
WHERE issue_key IN (
    SELECT source_issue_key FROM jira_issue_links
    UNION
    SELECT target_issue_key FROM jira_issue_links
);

-- Для Graphviz DOT формата
SELECT 
    'digraph G {' || E'\n' ||
    string_agg(
        '  "' || source_issue_key || '" -> "' || target_issue_key || 
        '" [label="' || direction_label || '"];',
        E'\n'
    ) || E'\n' ||
    '}'
FROM jira_issue_links;

-- Для Mermaid диаграмм
SELECT 
    'graph LR' || E'\n' ||
    string_agg(
        '  ' || source_issue_key || '[' || source_issue_key || '] -->|' || 
        direction_label || '| ' || target_issue_key || '[' || target_issue_key || ']',
        E'\n'
    )
FROM jira_issue_links
LIMIT 20;  -- Ограничиваем для читаемости