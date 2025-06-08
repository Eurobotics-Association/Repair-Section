@echo off
rem Initiator.bat – Installation automatique de Python, pip, magic-wormhole, ClamWin, 7-Zip et RustDesk
rem Prérequis : exécuter en tant qu'administrateur, cmd.exe, certutil (intégré dans Windows 7+)

setlocal EnableDelayedExpansion

\:: Vérification des droits administrateurs
net session >nul 2>&1 || (
echo \[ERROR] Droits administrateur requis.
pause
exit /b 1
)

\:: Préparation du dossier d'installation et du log
set "INSTALL\_DIR=%CD%\installers"
set "LOG\_FILE=%CD%\install\_log.txt"
if not exist "%INSTALL\_DIR%" mkdir "%INSTALL\_DIR%"
echo Installation démarrée à %DATE% %TIME% > "%LOG\_FILE%"

\:: Initialisation des statuts
for %%X in PY WORM CLAM 7Z RUST do set "STATUS\_%%X=Pending"

\:: Fonction : téléchargement via certutil
\:DownloadAndCheck
rem %1 = URL  |  %2 = Chemin complet de destination
certutil -urlcache -split -f "%\~1" "%\~2" >nul 2>&1
if exist "%\~2" (
echo \[INFO] Téléchargement réussi : %\~1 >> "%LOG\_FILE%"
set "LAST\_STATUS=OK"
) else (
echo \[ERROR] Téléchargement échoué : %\~1 >> "%LOG\_FILE%"
set "LAST\_STATUS=FAIL"
)
goto \:eof

\:: ----------------------------------------
\:: 1) Python + magic-wormhole
echo.
echo ===== Python + magic-wormhole =====
where python >nul 2>&1
if errorlevel 1 (
set "PY\_EXE=%INSTALL\_DIR%\python.exe"
call \:DownloadAndCheck "[https://www.python.org/ftp/python/3.11.4/python-3.11.4-amd64.exe](https://www.python.org/ftp/python/3.11.4/python-3.11.4-amd64.exe)" "%PY\_EXE%"
if "%LAST\_STATUS%"=="OK" (
"%PY\_EXE%" /quiet InstallAllUsers=1 PrependPath=1 >> "%LOG\_FILE%" 2>&1 && set "STATUS\_PY=OK" || set "STATUS\_PY=FAIL"
pip install magic-wormhole >> "%LOG\_FILE%" 2>&1 && set "STATUS\_WORM=OK" || set "STATUS\_WORM=FAIL"
) else (
set "STATUS\_PY=FAIL"
set "STATUS\_WORM=FAIL"
)
) else (
echo \[SKIP] Python déjà installé.
set "STATUS\_PY=Already"
set "STATUS\_WORM=Already"
echo Python: déjà installé >> "%LOG\_FILE%"
echo magic-wormhole: déjà installé >> "%LOG\_FILE%"
)

\:: ----------------------------------------
\:: 2) ClamWin Antivirus
echo.
echo ===== ClamWin Antivirus =====
reg query "HKLM\Software\ClamWin" >nul 2>&1
if errorlevel 1 (
set "CLAM\_EXE=%INSTALL\_DIR%\clamwin.exe"
call \:DownloadAndCheck "[https://downloads.sourceforge.net/project/clamwin/clamwin/1.1.0.1/clamwin-1.1.0.1-setup.exe](https://downloads.sourceforge.net/project/clamwin/clamwin/1.1.0.1/clamwin-1.1.0.1-setup.exe)" "%CLAM\_EXE%"
if "%LAST\_STATUS%"=="OK" (
"%CLAM\_EXE%" /silent >> "%LOG\_FILE%" 2>&1 && set "STATUS\_CLAM=OK" || set "STATUS\_CLAM=FAIL"
) else (
set "STATUS\_CLAM=FAIL"
)
) else (
echo \[SKIP] ClamWin déjà installé.
set "STATUS\_CLAM=Already"
echo ClamWin: déjà installé >> "%LOG\_FILE%"
)

\:: ----------------------------------------
\:: 3) 7-Zip
echo.
echo ===== 7-Zip =====
where 7z >nul 2>&1
if errorlevel 1 (
set "ZIP\_EXE=%INSTALL\_DIR%\7z.exe"
call \:DownloadAndCheck "[https://www.7-zip.org/a/7z2301-x64.exe](https://www.7-zip.org/a/7z2301-x64.exe)" "%ZIP\_EXE%"
if "%LAST\_STATUS%"=="OK" (
"%ZIP\_EXE%" /S >> "%LOG\_FILE%" 2>&1 && set "STATUS\_7Z=OK" || set "STATUS\_7Z=FAIL"
) else (
set "STATUS\_7Z=FAIL"
)
) else (
echo \[SKIP] 7-Zip déjà installé.
set "STATUS\_7Z=Already"
echo 7-Zip: déjà installé >> "%LOG\_FILE%"
)

\:: ----------------------------------------
\:: 4) RustDesk
echo.
echo ===== RustDesk =====
reg query "HKLM\Software\RustDesk" >nul 2>&1
if errorlevel 1 (
set "RUST\_EXE=%INSTALL\_DIR%\rustdesk.exe"
call \:DownloadAndCheck "[https://github.com/rustdesk/rustdesk/releases/download/1.2.0/rustdesk-1.2.0-win.exe](https://github.com/rustdesk/rustdesk/releases/download/1.2.0/rustdesk-1.2.0-win.exe)" "%RUST\_EXE%"
if "%LAST\_STATUS%"=="OK" (
"%RUST\_EXE%" /S >> "%LOG\_FILE%" 2>&1 && set "STATUS\_RUST=OK" || set "STATUS\_RUST=FAIL"
) else (
set "STATUS\_RUST=FAIL"
)
) else (
echo \[SKIP] RustDesk déjà installé.
set "STATUS\_RUST=Already"
echo RustDesk: déjà installé >> "%LOG\_FILE%"
)

\:: ----------------------------------------
\:: Récapitulatif et retour final
echo.
echo ===== Résultats =====
echo Python           %STATUS\_PY%
echo magic-wormhole  %STATUS\_WORM%
echo ClamWin          %STATUS\_CLAM%
echo 7-Zip            %STATUS\_7Z%
echo RustDesk         %STATUS\_RUST%
echo.
set "FAIL=0"
for %%X in PY WORM CLAM 7Z RUST do if "!STATUS\_%%X!"=="FAIL" set "FAIL=1"
if %FAIL%==1 (
echo \[ERROR] Certaines installations ont échoué. Voir %LOG\_FILE%
) else (
echo \[OK] Toutes les installations ont réussi.
)
echo.
pause
