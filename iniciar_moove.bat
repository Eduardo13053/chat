@echo off
cd /d "%~dp0"
where php >nul 2>nul
if errorlevel 1 (
  echo PHP nao foi encontrado. Instale PHP 8.1+ e adicione ao PATH.
  echo Consulte COMECE_AQUI.txt.
  pause
  exit /b 1
)
echo Moove iniciado: http://localhost:8000
echo Para parar, pressione Ctrl+C.
php -S localhost:8000 router.php
pause
