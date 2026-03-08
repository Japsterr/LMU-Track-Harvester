@echo off
call C:\PROGRA~2\EMBARC~1\Studio\23.0\bin\rsvars.bat
if errorlevel 1 exit /b %errorlevel%

if not exist "C:\LMU Harvester\build-temp" mkdir "C:\LMU Harvester\build-temp"
if exist "%~dp0branding\app-icon.ico" (
	powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0prepare_branding.ps1"
	if errorlevel 1 exit /b %errorlevel%
)

msbuild "C:\LMU Harvester\LMUTrackHarvester.dproj" /t:Build /p:Config=Release /p:Platform=Win64 /p:DCC_ExeOutput="C:\LMU Harvester\build-temp"
exit /b %errorlevel%