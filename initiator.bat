@echo off
setlocal EnableDelayedExpansion

:: =============================================================
:: INITIATOR - Script d'installation et de mise à jour
:: Licence GNU
:: Batch Script - par Eurobotics Association - V.20250607-Win7Fix
:: =============================================================

set "TMPDIR=%TEMP%\installers"
if not exist "%TMPDIR%" mkdir "%TMPDIR%"
set "LOGFILE=%TMPDIR%\install_log.txt"
echo [INITIATOR LOG - %DATE% %TIME%] > "%LOGFILE%"

set "STAT_PY=🕵️"
set "STAT_PIP=🕵️"
set "STAT_WORM=🕵️"
set "STAT_7Z=🕵️"
set "STAT_CLAM=🕵️"

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Ce script doit être lancé en tant qu'administrateur.
    pause
    exit /b
)

:: Function to download a file using a temporary PowerShell script
:DownloadAndCheck
:: %1 = URL, %2 = OutputFile
set "PS1_FILE=%TMPDIR%\download.ps1"
echo try { > "%PS1_FILE%"
echo   Invoke-WebRequest -Uri '%~1' -OutFile '%~2' -UseBasicParsing >> "%PS1_FILE%"
echo   if (!(Test-Path '%~2')) { Write-Error "Fichier non téléchargé."; exit 1 } >> "%PS1_FILE%"
echo } catch { Write-Error "Erreur de téléchargement : $_"; exit 1 } >> "%PS1_FILE%"
powershell -ExecutionPolicy Bypass -File "%PS1_FILE%"
del "%PS1_FILE%" >nul 2>&1
if not exist "%~2" (
    echo ❌ Erreur : fichier non téléchargé : %~2 >> "%LOGFILE%"
    echo ❌ Téléchargement échoué : %~2
    exit /b 1
)
goto :eof

:fail
set "FAIL_FLAG=1"
echo ❌ %~1 >> "%LOGFILE%"
echo ❌ %~1
goto :eof

:: ---- 1. Python ----
echo [1/5] Vérification ou installation de Python...
echo [PYTHON] Vérification... >> "%LOGFILE%"
where python >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "(Invoke-WebRequest -UseBasicParsing https://www.python.org/downloads/windows/).Content | Select-String -Pattern 'python-(\d+\.\d+\.\d+)-amd64\.exe' -AllMatches | ForEach-Object { $_.Matches } | Select-Object -First 1 | ForEach-Object { $_.Value }" > "%TMPDIR%\python_filename.txt"
    if exist "%TMPDIR%\python_filename.txt" (
        set /p PYTHON_EXE=<"%TMPDIR%\python_filename.txt"
        echo [PYTHON] Fichier détecté : %PYTHON_EXE% >> "%LOGFILE%"
        call :DownloadAndCheck https://www.python.org/ftp/python/%PYTHON_EXE:python-=% "%TMPDIR%\python.exe" || (set "STAT_PY=FAIL" & goto :eof)
        "%TMPDIR%\python.exe" /quiet InstallAllUsers=1 PrependPath=1 Include_pip=1 && set "STAT_PY=OK" || (set "STAT_PY=FAIL" & call :fail "Installation Python échouée.")
    ) else (
        call :fail "Nom de fichier Python introuvable."
        set "STAT_PY=FAIL"
    )
) else (
    set "STAT_PY=Déjà installé"
    python -m pip install --upgrade pip && set "STAT_PIP=OK" || set "STAT_PIP=FAIL"
)

:: ---- 2. Wormhole ----
echo [2/5] Installation ou mise à jour de Wormhole...
python -m pip show magic-wormhole >nul 2>&1
if %errorlevel% neq 0 (
    python -m pip install magic-wormhole && set "STAT_WORM=OK" || set "STAT_WORM=FAIL"
) else (
    python -m pip install --upgrade magic-wormhole && set "STAT_WORM=Déjà installé" || set "STAT_WORM=FAIL"
)

:: ---- 3. ClamWin ----
echo [3/5] Installation de ClamWin Antivirus...
powershell -Command "(Invoke-WebRequest -UseBasicParsing https://sourceforge.net/projects/clamwin/rss?path=/) | Select-String -Pattern 'clamwin-([\d.]+)-setup.exe' -AllMatches | ForEach-Object { $_.Matches } | Select-Object -First 1 | ForEach-Object { $_.Value }" > "%TMPDIR%\clamwin_filename.txt"
if exist "%TMPDIR%\clamwin_filename.txt" (
    set /p CLAMWIN_EXE=<"%TMPDIR%\clamwin_filename.txt"
    echo [CLAMWIN] Fichier détecté : %CLAMWIN_EXE% >> "%LOGFILE%"
    call :DownloadAndCheck https://downloads.sourceforge.net/clamwin/%CLAMWIN_EXE% "%TMPDIR%\clamwin.exe" || (set "STAT_CLAM=FAIL" & goto :eof)
    "%TMPDIR%\clamwin.exe" /sp- /verysilent /norestart && set "STAT_CLAM=OK" || (set "STAT_CLAM=FAIL" & call :fail "Installation ClamWin échouée.")
) else (
    call :fail "Nom du fichier ClamWin introuvable."
    set "STAT_CLAM=FAIL"
)

:: ---- 4. 7-Zip ----
echo [4/5] Vérification ou installation de 7-Zip...
where 7z >nul 2>&1
if %errorlevel% neq 0 (
    if exist "C:\Program Files\7-Zip\7z.exe" (
        set "STAT_7Z=Déjà installé"
    ) else (
        powershell -Command "(Invoke-WebRequest -UseBasicParsing https://www.7-zip.org/).Content | Select-String -Pattern '7z(\d+)-x64\.exe' -AllMatches | ForEach-Object { $_.Matches } | Select-Object -First 1 | ForEach-Object { $_.Value }" > "%TMPDIR%\7zip_filename.txt"
        if exist "%TMPDIR%\7zip_filename.txt" (
            set /p SEVENZIP_EXE=<"%TMPDIR%\7zip_filename.txt"
            echo [7ZIP] Fichier détecté : %SEVENZIP_EXE% >> "%LOGFILE%"
            call :DownloadAndCheck https://www.7-zip.org/a/%SEVENZIP_EXE% "%TMPDIR%\7zip.exe" || (set "STAT_7Z=FAIL" & goto :eof)
            "%TMPDIR%\7zip.exe" /S && set "STAT_7Z=OK" || (set "STAT_7Z=FAIL" & call :fail "Installation 7-Zip échouée.")
        ) else (
            call :fail "Nom du fichier 7-Zip introuvable."
            set "STAT_7Z=FAIL"
        )
    )
) else (
    set "STAT_7Z=Déjà installé"
)

:: ---- Résumé ----
echo.
echo ================= RÉCAPITULATIF =================
echo Python .......... %STAT_PY%
echo pip ............. %STAT_PIP%
echo Wormhole ........ %STAT_WORM%
echo ClamWin ......... %STAT_CLAM%
echo 7-Zip ........... %STAT_7Z%

echo.
if defined FAIL_FLAG (
    echo ⚠️ Certaines installations sont incomplètes. Voir les statuts ci-dessus.
    echo 🔍 Journal : %LOGFILE%
    start notepad "%LOGFILE%"
) else (
    echo ✅ Tous les outils sont installés ou à jour.
)

pause
exit /b
