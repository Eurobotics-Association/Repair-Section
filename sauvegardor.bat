echo off
chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion

:: =============================================
:: SAUVEGARDOR.BAT - Sauvegarde compressée des répertoires utilisateurs
:: Compatible Windows 7, 10, 11 - Exécution Admin requise
:: Eurobotics - GNU - v.20250609
:: =============================================

:: === Configuration Debug ===
set "DEBUG=0"
if "%DEBUG%"=="1" echo on

:: === Vérifier les droits admin ===
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERREUR] Ce script doit etre lance en tant qu'administrateur.
    pause
    exit /b 1
)

:: === Forcer PowerShell si présent (redémarrage automatique si nécessaire) ===
where powershell >nul 2>&1
if %errorlevel%==0 (
    powershell -Command "if (-not [Environment]::UserInteractive) { exit 0 }"
    if not defined PROMPT (
        echo [INFO] Redemarrage dans PowerShell avec droits admin...
        powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%~f0\"' -Verb runAs"
        exit /b
    )
) else (
    echo [AVERTISSEMENT] PowerShell non detecte. Certaines fonctionnalites seront limitees.
)

:: === Vérifier la présence de 7z.exe dans le PATH ou dans C:\Program Files\7-Zip ===
where 7z.exe >nul 2>&1
if %errorlevel% neq 0 (
    if exist "C:\Program Files\7-Zip\7z.exe" (
        set "PATH=C:\Program Files\7-Zip;%PATH%"
        echo [INFO] 7-Zip detecte manuellement dans C:\Program Files\7-Zip
    ) else (
        echo [ERREUR] 7-Zip non detecte dans le PATH ni dans C:\Program Files\7-Zip
        echo Merci de l'installer depuis https://www.7-zip.org
        pause
        exit /b 1
    )
)

:: === Vérifier que le script n'est pas lancé depuis un sous-répertoire de C:\Users\ ===
echo %CD% | findstr /i "^C:\\Users\\" >nul
if %errorlevel%==0 (
    powershell -Command "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; Write-Host '[ERREUR] Changer de repertoire pour eviter l''auto-zippage!' -ForegroundColor Red"
    pause
    exit /b 1
)

:: === Afficher la version de 7-Zip ===
7z.exe | find "7-Zip" && echo [INFO] Version de 7-Zip detectee.

:: === Variables globales ===
set "CURDIR=%CD%"
set "LOG_FILE=%CURDIR%\sauvegardor_log.txt"
set "PCNAME=%COMPUTERNAME%"
if exist "%LOG_FILE%" del /f /q "%LOG_FILE%"

call :EnableLog

:MainMenu
call :LogEcho "================= MENU SAUVEGARDOR ================="
where powershell >nul 2>&1
if %errorlevel%==0 (
    powershell -Command "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; Write-Host '[A] Sauvegarder un utilisateur (archive unique, taille illimitée)' -ForegroundColor Yellow"
    powershell -Command "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; Write-Host '    → Un seul fichier .7z, même si > 20Go' -ForegroundColor Gray"
    powershell -Command "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; Write-Host '[B] Sauvegarder TOUS les utilisateurs avec fragmentation 20Go' -ForegroundColor Yellow"
    powershell -Command "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; Write-Host '[C] Sauvegarder un utilisateur avec fragmentation 20Go' -ForegroundColor Yellow"
    powershell -Command "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; Write-Host '[Q] Quitter' -ForegroundColor Cyan"
) else (
    call :LogEcho "[A] Sauvegarder un utilisateur (archive unique, taille illimitée)"
    call :LogEcho "    → Un seul fichier .7z, même si > 20Go"
    call :LogEcho "[B] Sauvegarder TOUS les utilisateurs avec fragmentation 20Go"
    call :LogEcho "[C] Sauvegarder un utilisateur avec fragmentation 20Go"
    call :LogEcho "[Q] Quitter"
)
set /p CHOIX=Choix : 

if /i "%CHOIX%"=="A" goto MenuChoixA
if /i "%CHOIX%"=="B" goto MenuChoixB
if /i "%CHOIX%"=="C" goto MenuChoixC
if /i "%CHOIX%"=="Q" exit /b 0
call :LogEcho "Choix invalide."
goto MainMenu

:MenuChoixA
call :AfficherListeEtChoisirUtilisateur
call :EstimerEtZipper "C:\Users\!TARGET!" "false"
goto MainMenu

:MenuChoixB
for /f "delims=" %%d in ('dir /b /ad "C:\Users" ^| findstr /v /i "All Users Default Default User"') do (
    if exist "C:\Users\%%d\NTUSER.DAT" (
        call :NettoyerNomArchive "%%d"
        call :EstimerEtZipper "C:\Users\%%d" "true"
    )
)
goto MainMenu

:MenuChoixC
call :AfficherListeEtChoisirUtilisateur
call :EstimerEtZipper "C:\Users\!TARGET!" "true"
goto MainMenu

:AfficherListeEtChoisirUtilisateur
call :LogEcho "[ACTION] Liste des repertoires utilisateurs..."
set i=0
for /f "delims=" %%d in ('dir /b /ad "C:\Users" ^| findstr /v /i "All Users Default Default User"') do (
    if exist "C:\Users\%%d\NTUSER.DAT" (
        set /a i+=1
        set "user[!i!]=%%d"
        powershell -Command "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; Write-Host '!i!. %%d' -ForegroundColor Green"
    )
)
if %i%==0 call :LogEcho "[AVERTISSEMENT] Aucun utilisateur détecté. L'encodage PowerShell peut être incomplet."
set /p USERIDX=Numero du repertoire a sauvegarder : 
set "USERIDX=%USERIDX: =%"
call :LogEcho "[DEBUG] USERIDX=%USERIDX%"
set "TARGET=!user[%USERIDX%]!"
if not defined TARGET (
    call :LogEcho "[ERREUR] Mauvaise sélection ou variable non initialisée."
    goto MainMenu
)
call :LogEcho "[INFO] Cible: !TARGET!"
call :NettoyerNomArchive "!TARGET!"
exit /b

:NettoyerNomArchive
set "RAWNAME=%~1"
set "ARCHNAME=%RAWNAME%"
set "ARCHNAME=!ARCHNAME:é=e!"
set "ARCHNAME=!ARCHNAME:è=e!"
set "ARCHNAME=!ARCHNAME:ê=e!"
set "ARCHNAME=!ARCHNAME:ë=e!"
set "ARCHNAME=!ARCHNAME:à=a!"
set "ARCHNAME=!ARCHNAME:ù=u!"
set "ARCHNAME=!ARCHNAME:ô=o!"
set "ARCHNAME=!ARCHNAME:î=i!"
set "ARCHNAME=!ARCHNAME:ï=i!"
set "ARCHNAME=!ARCHNAME:ç=c!"
set "ARCHNAME=!ARCHNAME: =_!"
set "ARCHNAME=!ARCHNAME:^<=!"
set "ARCHNAME=!ARCHNAME:^>=!"
set "ARCHNAME=!ARCHNAME:^&=and!"
set "ARCHNAME=!ARCHNAME:^|=!"
set "ARCHNAME=!ARCHNAME:^'=!"
set "ARCHNAME=!ARCHNAME:^\"=!"
set "ARCHNAME=!ARCHNAME:^`=!"
set "CLEANNAME=!ARCHNAME!"
if not "%RAWNAME%"=="%CLEANNAME%" call :LogEcho "[NOTE] Nom d'archive nettoyé : %RAWNAME% -> !CLEANNAME!"
exit /b

:EstimerEtZipper
set "FOLDER=%~1"
set "SPLIT=%~2"
set "ARCHIVE=%CURDIR%\!CLEANNAME!_%PCNAME%_%DATE:/=%"

if not exist "!FOLDER!" (
    call :LogEcho "[ERREUR] Dossier inexistant : !FOLDER!"
    exit /b 1
)

call :LogEcho "[INFO] Lancement compression 7z sur !FOLDER!"
if "%SPLIT%"=="true" (
    7z.exe a -v20g -mx9 -t7z "!ARCHIVE!.7z" "!FOLDER!\*" -snl >> "%LOG_FILE%" 2>&1
) else (
    7z.exe a -mx9 -t7z "!ARCHIVE!.7z" "!FOLDER!\*" -snl >> "%LOG_FILE%" 2>&1
)
if errorlevel 1 (
    call :LogEcho "[ERREUR] Compression echouee : !FOLDER!"
) else (
    call :LogEcho "[OK] Archive creee : !ARCHIVE!.7z"
)
exit /b 0

:LogEcho
echo %~1
echo %~1 >> "%LOG_FILE%"
exit /b

:EnableLog
exit /b
