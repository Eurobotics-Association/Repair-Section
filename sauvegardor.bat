@echo on

:: =============================================
:: SAUVEGARDOR.BAT - Sauvegarde compressée des répertoires utilisateurs
:: Compatible Windows 7, 10, 11 - Exécution Admin requise
:: =============================================

:: === Vérifier les droits admin ===
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERREUR] Ce script doit être lancé en tant qu'administrateur.
    pause
    exit /b 1
)

:: === Vérifier la présence de PowerShell (optionnelle mais utile) ===
where powershell >nul 2>&1 || (
    echo [AVERTISSEMENT] PowerShell non détecté. Certaines fonctionnalités seront limitées.
)

:: === Vérifier la présence de 7z.exe dans le PATH ===
where 7z.exe >nul 2>&1
if errorlevel 1 (
    echo [ERREUR] 7-Zip n'est pas installé ou non présent dans le PATH.
    echo Merci d'installer 7-Zip (https://www.7-zip.org/) et de redémarrer le script.
    pause
    exit /b 1
)

:: === Variables globales ===
setlocal EnableExtensions EnableDelayedExpansion
set "CURDIR=%CD%"
set "LOG_FILE=%CURDIR%\sauvegardor_log.txt"
set "PCNAME=%COMPUTERNAME%"
if exist "%LOG_FILE%" del /f /q "%LOG_FILE%"

:: === Fonctions ===
:MainMenu
echo.
echo ================= MENU SAUVEGARDOR ================= > "%LOG_FILE%"
echo A. Lister les répertoires utilisateurs et zipper 1 au choix
echo B. Sauvegarder tous les répertoires utilisateurs (fragmentation si nécessaire)
echo C. Sauvegarder un répertoire avec fragmentation 20Go
echo Q. Quitter
set /p CHOIX=Choix : 

if /i "%CHOIX%"=="A" goto MenuChoixA
if /i "%CHOIX%"=="B" goto MenuChoixB
if /i "%CHOIX%"=="C" goto MenuChoixC
if /i "%CHOIX%"=="Q" exit /b 0
echo Choix invalide.
goto MainMenu

:MenuChoixA
echo [ACTION] Liste des répertoires utilisateurs...
set i=0
for /d %%d in (C:\Users\*) do (
    set /a i+=1
    set "user[!i!]=%%~nd"
    echo !i!. %%~nd
)
set /p USERIDX=Numéro du répertoire à sauvegarder : 
set "TARGET=!user[%USERIDX%]!"
if not defined TARGET (
    echo [ERREUR] Sélection invalide.
    goto MainMenu
)
call :EstimerEtZipper "C:\Users\%TARGET%" "false"
goto MainMenu

:MenuChoixB
for /d %%d in (C:\Users\*) do (
    call :EstimerEtZipper "%%~fd" "true"
)
goto MainMenu

:MenuChoixC
echo [ACTION] Liste des répertoires utilisateurs...
set i=0
for /d %%d in (C:\Users\*) do (
    set /a i+=1
    set "user[!i!]=%%~nd"
    echo !i!. %%~nd
)
set /p USERIDX=Numéro du répertoire à sauvegarder : 
set "TARGET=!user[%USERIDX%]!"
if not defined TARGET (
    echo [ERREUR] Sélection invalide.
    goto MainMenu
)
call :EstimerEtZipper "C:\Users\%TARGET%" "true"
goto MainMenu

:: === Fonction estimation + compression ===
:EstimerEtZipper
set "FOLDER=%~1"
set "SPLIT=%~2"
set "ARCHIVE=%CURDIR%\%~nx1_%PCNAME%_%DATE:/=%.7z"

:: Taille non compressée (en octets)
for /f "tokens=3" %%s in ('dir /s /-c "%FOLDER%" ^| find "octets"') do set "SIZE=%%s"
set "SIZE=!SIZE:,=!"
set /a ESTIMATED=!SIZE! * 60 / 100

:: Espace disque libre
for /f %%f in ('powershell -NoProfile -Command "(Get-PSDrive -Name $env:SystemDrive[0]).Free"') do set "FREESPACE=%%f"
if !FREESPACE! LSS !ESTIMATED! (
    echo [ERREUR] Espace disque insuffisant pour compresser !FOLDER! >> "%LOG_FILE%"
    echo [ERREUR] Espace disque insuffisant
    exit /b 1
)

:: Compression
if "%SPLIT%"=="true" (
    7z.exe a -v20g -mx9 -t7z "!ARCHIVE!" "%FOLDER%" >> "%LOG_FILE%"
) else (
    7z.exe a -mx9 -t7z "!ARCHIVE!" "%FOLDER%" >> "%LOG_FILE%"
)
if errorlevel 1 (
    echo [ERREUR] Échec de la compression de !FOLDER! >> "%LOG_FILE%"
    echo [ERREUR] Compression échouée : !FOLDER!
) else (
    echo [OK] Archive créée : !ARCHIVE! >> "%LOG_FILE%"
    echo [OK] Archive créée : !ARCHIVE!
)
exit /b 0
