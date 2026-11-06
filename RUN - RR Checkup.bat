@echo off
REM RR Checkup - reads your hardware and writes an Upgrade Report to the Desktop.
REM Read-only.  No admin needed.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0RR-Checkup.ps1"
