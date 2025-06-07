@echo off
setlocal EnableDelayedExpansion

:: =============================================================
:: INITIATOR - Script d'installation et de mise à jour
:: Licence GNU 
:: Batch Script - par Eurobotics Association - V.20250606
:: -------------------------------------------------------------
:: Ce script :
:: 1. Installe ou met à jour Python depuis python.org
:: 2. Installe ou met à jour Wormhole (magic-wormhole via pip)
:: 3. Télécharge et installe ClamWin Antivirus depuis SourceForge
:: 4. Télécharge et installe 7-Zip depuis 7-zip.org
:: Chaque outil est vérifié, téléchargé automatiquement si absent,
:: et installé en version la plus récente.
:: En fin de script, un récapitulatif affiche les statuts simples :
:: ✅ OK - ❌ FAIL - 🔁 Déjà installé
:: =============================================================

:: Vérification de droits administrateur
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Ce script doit être lancé en tant qu'administrateur.
    pause
    exit /b
)

:: Création du dossier temporaire
set "TMPDIR=%TEMP%\installers"
if not exist "%TMPDIR%" mkdir "%TMPDIR%"

:: Variables de statut
set "STAT_PY=❌"
set "STAT_PIP=❌"
set "STAT_WORM=❌"
set "STAT_7Z=❌"
set "STAT_CLAM=❌"

:: ---- 1. Python ----
echo [1/5] Vérification ou installation de Python...
where python >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "(Invoke-WebRequest -UseBasicParsing https://www.python.org/downloads/windows/).Content | Select-String -Pattern 'python-(\d+\.\d+\.\d+)-amd64\.exe' -AllMatches | ForEach-Object { $_.Matches } | Select-Object -First 1 | ForEach-Object { $_.Value }" > "%TMPDIR%\python_filename.txt"
    set /p PYTHON_EXE=<"%TMPDIR%\python_filename.txt"
    powershell -Command "Invoke-WebRequest https://www.python.org/ftp/python/%PYTHON_EXE:python-=% -OutFile '%TMPDIR%\python.exe'"
    "%TMPDIR%\python.exe" /quiet InstallAllUsers=1 PrependPath=1 Include_pip=1 && set "STAT_PY=OK" || set "STAT_PY=FAIL"
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
set /p CLAMWIN_EXE=<"%TMPDIR%\clamwin_filename.txt"
powershell -Command "Invoke-WebRequest https://downloads.sourceforge.net/clamwin/%CLAMWIN_EXE% -OutFile '%TMPDIR%\clamwin.exe'"
"%TMPDIR%\clamwin.exe" /sp- /verysilent /norestart && set "STAT_CLAM=OK" || set "STAT_CLAM=FAIL"

:: ---- 4. 7-Zip ----
echo [4/5] Vérification ou installation de 7-Zip...
where 7z >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "(Invoke-WebRequest -UseBasicParsing https://www.7-zip.org/).Content | Select-String -Pattern '7z(\d+)-x64\.exe' -AllMatches | ForEach-Object { $_.Matches } | Select-Object -First 1 | ForEach-Object { $_.Value }" > "%TMPDIR%\7zip_filename.txt"
    set /p SEVENZIP_EXE=<"%TMPDIR%\7zip_filename.txt"
    powershell -Command "Invoke-WebRequest https://www.7-zip.org/a/%SEVENZIP_EXE% -OutFile '%TMPDIR%\7zip.exe'"
    "%TMPDIR%\7zip.exe" /S && set "STAT_7Z=OK" || set "STAT_7Z=FAIL"
) else (
    set "STAT_7Z=Déjà installé"
)

:: ---- Ajout manuel au PATH (vérifié avant) ----
set "SEVENZIP_PATH=C:\Program Files\7-Zip"
if exist "%SEVENZIP_PATH%\7z.exe" (
    echo Ajout de 7-Zip au PATH système si nécessaire...
    echo %PATH% | find /I "%SEVENZIP_PATH%" >nul
    if errorlevel 1 (
        setx PATH "%PATH%;%SEVENZIP_PATH%" /M
    )
)

:: ---- Récapitulatif ----
echo.
echo ================= RÉCAPITULATIF =================
echo Python .......... %STAT_PY%
echo pip ............. %STAT_PIP%
echo Wormhole ........ %STAT_WORM%
echo ClamWin ......... %STAT_CLAM%
echo 7-Zip ........... %STAT_7Z%

echo.
if "%STAT_PY%%STAT_WORM%%STAT_CLAM%%STAT_7Z%" == "OKOKOKOK" (
    echo ✅ Tous les outils sont installés et à jour.
) else (
    echo ⚠️ Certaines installations sont incomplètes. Voir les statuts ci-dessus.
)
echo.
pause
