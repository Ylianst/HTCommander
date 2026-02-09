@echo off
REM HTCommander Installer Build Script
REM This script builds the MSI installer for HTCommander
REM
REM Prerequisites:
REM   - .NET SDK 8.0 or later (for WiX 5.0)
REM   - WiX Toolset will be automatically downloaded via NuGet
REM
REM Usage:
REM   build-installer.bat [Debug|Release]
REM

setlocal

REM Default to Release if no configuration specified
set CONFIG=%1
if "%CONFIG%"=="" set CONFIG=Release

echo.
echo ============================================
echo  HTCommander Installer Build
echo  Configuration: %CONFIG%
echo ============================================
echo.

REM Navigate to the setup directory
cd /d "%~dp0"

REM First, build the main HTCommander project
echo Building HTCommander application...
dotnet build ..\src\HTCommander.csproj -c %CONFIG%
if errorlevel 1 (
    echo.
    echo ERROR: Failed to build HTCommander application
    exit /b 1
)

REM Publish the application for self-contained deployment
echo.
echo Publishing HTCommander application...
dotnet publish ..\src\HTCommander.csproj -c %CONFIG% -r win-x64 --self-contained false -o ..\src\bin\%CONFIG%\publish
if errorlevel 1 (
    echo.
    echo ERROR: Failed to publish HTCommander application
    exit /b 1
)

REM Build the WiX installer
echo.
echo Building MSI installer...
dotnet build HTCommander.Installer.wixproj -c %CONFIG%
if errorlevel 1 (
    echo.
    echo ERROR: Failed to build MSI installer
    exit /b 1
)

echo.
echo ============================================
echo  Build completed successfully!
echo  MSI location: bin\%CONFIG%\HTCommander.msi
echo ============================================
echo.

endlocal