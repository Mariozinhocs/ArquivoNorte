@echo off
title Gerador de Licencas - ArquivoNorte
start "" powershell.exe -ExecutionPolicy Bypass -NoProfile -STA -WindowStyle Hidden -File "%~dp0Gerador-Licencas.ps1"
exit
