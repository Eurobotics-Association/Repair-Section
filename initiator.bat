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

:: ---- 1. Télécharger et installer / mettre à jour Python ----
echo [1/4] Vérification ou installation de Python...
where python >nul 2>&1
if %errorlevel% neq 0 (
    echo Python non détecté. Téléchargement...
    powershell -Command "(Invoke-WebRequest -UseBasicParsing https://www.python.org/downloads/windows/).Content | Select-String -Pattern 'python-(\d+\.\d+\.\d+)-amd64\.exe' -AllMatches | ForEach-Object { $_.Matches } | Select-Object -First 1 | ForEach-Object { $_.Value }" > "%TMPDIR%\python_filename.txt"
    set /p PYTHON_EXE=<"%TMPDIR%\python_filename.txt"
    powershell -Command "Invoke-WebRequest https://www.python.org/ftp/python/%PYTHON_EXE:python-=% -OutFile '%TMPDIR%\python.exe'"
    "%TMPDIR%\python.exe" /quiet InstallAllUsers=1 PrependPath=1 Include_pip=1
) else (
    echo Python déjà installé. Mise à jour de pip...
    python -m pip install --upgrade pip
)

:: ---- 2. Installer / mettre à jour Wormhole ----
echo [2/4] Installation ou mise à jour de Wormhole (magic-wormhole)...
python -m pip show magic-wormhole >nul 2>&1
if %errorlevel% neq 0 (
    echo Wormhole non détecté. Installation...
    python -m pip install magic-wormhole
) else (
    echo Wormhole détecté. Mise à jour...
    python -m pip install --upgrade magic-wormhole
)

:: ---- 3. Télécharger et installer / mettre à jour ClamWin ----
echo [3/4] Téléchargement de la dernière version de ClamWin...
powershell -Command "(Invoke-WebRequest -UseBasicParsing https://sourceforge.net/projects/clamwin/rss?path=/) | Select-String -Pattern 'clamwin-([\d.]+)-setup.exe' -AllMatches | ForEach-Object { $_.Matches } | Select-Object -First 1 | ForEach-Object { $_.Value }" > "%TMPDIR%\clamwin_filename.txt"
set /p CLAMWIN_EXE=<"%TMPDIR%\clamwin_filename.txt"
powershell -Command "Invoke-WebRequest https://downloads.sourceforge.net/clamwin/%CLAMWIN_EXE% -OutFile '%TMPDIR%\clamwin.exe'"
echo Installation silencieuse de ClamWin...
"%TMPDIR%\clamwin.exe" /sp- /verysilent /norestart

:: ---- 4. Télécharger et installer / mettre à jour 7-Zip ----
echo [4/4] Vérification ou installation de 7-Zip...
where 7z >nul 2>&1
if %errorlevel% neq 0 (
    echo 7-Zip non détecté. Téléchargement de la dernière version...
    powershell -Command "(Invoke-WebRequest -UseBasicParsing https://www.7-zip.org/).Content | Select-String -Pattern '7z(\d+)-x64\.exe' -AllMatches | ForEach-Object { $_.Matches } | Select-Object -First 1 | ForEach-Object { $_.Value }" > "%TMPDIR%\7zip_filename.txt"
    set /p SEVENZIP_EXE=<"%TMPDIR%\7zip_filename.txt"
    powershell -Command "Invoke-WebRequest https://www.7-zip.org/a/%SEVENZIP_EXE% -OutFile '%TMPDIR%\7zip.exe'"
    "%TMPDIR%\7zip.exe" /S
) else (
    echo 7-Zip déjà installé.
)

:: ---- Ajout de 7-Zip au PATH si nécessaire ----
set "SEVENZIP_PATH=C:\Program Files\7-Zip"
if exist "%SEVENZIP_PATH%\7z.exe" (
    echo Ajout de 7-Zip au PATH système si nécessaire...
    echo %PATH% | find /I "%SEVENZIP_PATH%" >nul
    if errorlevel 1 (
        setx PATH "%PATH%;%SEVENZIP_PATH%" /M
        echo 7-Zip ajouté au PATH.
    ) else (
        echo 7-Zip déjà présent dans le PATH.
    )
)

:: Résumé
where python >nul 2>&1 && echo Python OK || echo Python manquant
where pip >nul 2>&1 && echo pip OK || echo pip manquant
where wormhole >nul 2>&1 && echo Wormhole OK || echo Wormhole manquant
where 7z >nul 2>&1 && echo 7-Zip OK || echo 7-Zip manquant

:: ClamWin n’ajoute pas de commande dans le PATH par défaut

echo.
echo ✅ Mise à jour ou installation terminée. Python, Wormhole, ClamWin et 7-Zip sont prêts à l'emploi.
pause
