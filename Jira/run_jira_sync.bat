@echo off
chcp 65001 >nul
echo ===============================================
echo Запуск Jira Sync Script
echo ===============================================
echo.

REM Получаем директорию, где находится этот batch-файл
set "SCRIPT_DIR=%~dp0"
echo Директория скрипта: %SCRIPT_DIR%

REM Переход в директорию скрипта
cd /d "%SCRIPT_DIR%"
if %errorlevel% neq 0 (
    echo ОШИБКА: Не удалось перейти в директорию проекта
    pause
    exit /b 1
)

echo Текущая директория: %CD%
echo.

REM Активация виртуального окружения
echo Активация виртуального окружения...
call venv\Scripts\activate.bat
if %errorlevel% neq 0 (
    echo ОШИБКА: Не удалось активировать виртуальное окружение
    pause
    exit /b 1
)

echo Виртуальное окружение активировано
echo.

REM Запуск Python скрипта
echo Запуск скрипта jira_sync.py...
echo.
python jira_sync.py "labels=SEO AND assignee=currentUser() AND created >= startOfYear()"

if %errorlevel% neq 0 (
    echo.
    echo ===============================================
    echo СКРИПТ ЗАВЕРШИЛСЯ С ОШИБКОЙ
    echo ===============================================
    pause
    exit /b 1
)

echo.
echo ===============================================
echo СКРИПТ УСПЕШНО ВЫПОЛНЕН
echo ===============================================
exit