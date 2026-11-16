@echo off
rem Abre o widget do Claudinho sem janela de console.
rem O mod grava um JSON por sessao em <pasta do mod>\state\<sessionId>.json.
start "" powershell.exe -NoProfile -WindowStyle Hidden -STA -ExecutionPolicy Bypass -File "%~dp0claudinho-widget.ps1" -StateDir "%~dp0..\state"
