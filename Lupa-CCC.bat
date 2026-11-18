@echo off
title ArquivoNorte - A-Team
start "" powershell.exe -ExecutionPolicy Bypass -NoProfile -STA -WindowStyle Hidden -File "%~dp0Buscar-CCC.ps1"
exit
