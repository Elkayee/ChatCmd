@echo off
title ChatCMD - OpenAI Secure MCP Tunnel
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0openai-tunnel\openai-tunnel.ps1" %*
if errorlevel 1 pause
