@echo off
rem Binary-safe device screenshot capture.
rem Usage: capture_device_shot.bat <serial> <output-file-name-inside-docs>
setlocal
set SERIAL=%~1
set OUT=%~dp0docs\%~2
adb -s %SERIAL% exec-out screencap -p > "%OUT%"
endlocal
