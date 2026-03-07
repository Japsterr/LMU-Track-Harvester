@echo off
call C:\PROGRA~2\EMBARC~1\Studio\23.0\bin\rsvars.bat
if errorlevel 1 exit /b %errorlevel%

if not exist "C:\LMU Harvester\build-temp" mkdir "C:\LMU Harvester\build-temp"
msbuild "C:\LMU Harvester\LMUTrackHarvester.dproj" /t:Build /p:Config=Release /p:DCC_ExeOutput="C:\LMU Harvester\build-temp"
exit /b %errorlevel%