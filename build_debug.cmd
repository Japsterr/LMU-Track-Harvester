@echo off
call C:\PROGRA~2\EMBARC~1\Studio\23.0\bin\rsvars.bat
if errorlevel 1 exit /b %errorlevel%

if exist "%~dp0branding\app-icon.ico" (
	powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0prepare_branding.ps1"
	if errorlevel 1 exit /b %errorlevel%
)

msbuild "C:\LMU Harvester\LMUTrackHarvester.dproj" /t:Build /p:Config=Debug /p:Platform=Win64
exit /b %errorlevel%