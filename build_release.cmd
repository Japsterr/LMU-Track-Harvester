@echo off
call C:\PROGRA~2\EMBARC~1\Studio\23.0\bin\rsvars.bat
if errorlevel 1 exit /b %errorlevel%

msbuild "C:\LMU Harvester\LMUTrackHarvester.dproj" /t:Build /p:Config=Release
exit /b %errorlevel%