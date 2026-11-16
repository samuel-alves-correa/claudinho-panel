@echo off
rem Abre o widget do Claudinho sem janela de console.
rem O mod grava um JSON por sessao em %USERPROFILE%\.claude\claudinho\state\<sessionId>.json (padrao do widget).
start "" powershell.exe -NoProfile -WindowStyle Hidden -STA -ExecutionPolicy Bypass -File "%~dp0claudinho-widget.ps1"
