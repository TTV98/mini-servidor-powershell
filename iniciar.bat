@echo off
rem Abre o mini servidor e o navegador. Para parar, aperte Ctrl+C ou feche esta janela.
rem -ExecutionPolicy Bypass vale só para esta execução: não muda a configuração do Windows.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0servidor.ps1" -AbrirNavegador
pause
