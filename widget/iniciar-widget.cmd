@echo off
rem Abre o widget do Claudinho sem janela de console.
rem O estado e gravado pelo mod em <pasta do mod>\claudinho-state.json.
start "" powershell.exe -NoProfile -WindowStyle Hidden -STA -ExecutionPolicy Bypass -File "%~dp0claudinho-widget.ps1" -StateFile "%~dp0..\claudinho-state.json"
