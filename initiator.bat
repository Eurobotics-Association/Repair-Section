@echo off
setlocal EnableDelayedExpansion

\:: ----------------------------------------
\:: Vérification : Exécution en tant qu'administrateur
net session >nul 2>&1 || (
echo \[ERROR] Ce script doit être exécuté en tant qu'administrateur.
pause
exit /b 1
)

\:: Vérification : Exécution depuis PowerShell
if not defined PSModulePath (
echo \[ERROR] Veuillez lancer ce script depuis une console PowerShell, pas CMD.
pause
exit /b 1
)

\:: Définition des répertoires et du log
set "INSTALL\_DIR=%CD%\installers"
set "LOG\_FILE=%CD%\install\_log.txt"
if not exist "%INSTALL\_DIR%" mkdir "%INSTALL\_DIR%"
echo Installation démarrée à %DATE% %TIME% > "%LOG\_FILE%"

\:: Variables de statut
set "STATUS\_PY="
set "STATUS\_WORM="
set "STATUS\_CLAM="
set "STATUS\_7Z="
set "STATUS\_RUST="

\:: ----------------------------------------
\:: Fonction : Télécharger et vérifier
\:DownloadAndCheck
REM  %1 = URL  |  %2 = Chemin de destination complet
powershell -Command ^
"try { (New-Object Net.WebClient).DownloadFile('%\~1','%\~2') } catch { exit 1 }"
if exist "%\~2" (
echo \[INFO] Téléchargement réussi : %\~1 >> "%LOG\_FILE%"
set "LAST\_STATUS=OK"
) else (
echo \[ERROR] Échec du téléchargement : %\~1 >> "%LOG\_FILE%"
set "LAST\_STATUS=FAIL"
)
goto \:eof

\:: ----------------------------------------
\:: 1) Python + pip + magic-wormhole
echo.
echo ===== Python et magic-wormhole =====
where python >nul 2>&1
if !ERRORLEVEL! EQU 0 (
echo \[SKIP] Python déjà installé.
echo Python: Déjà installé >> "%LOG\_FILE%"
set "STATUS\_PY=🔁"
) else (
echo \[INFO] Récupération de la dernière version de Python...
set "PY\_EXEC=%INSTALL\_DIR%\python-latest-amd64.exe"
powershell -Command ^
"\$v = Invoke-WebRequest -UseBasicParsing '[https://www.python.org/ftp/python/](https://www.python.org/ftp/python/)' ^
\| Select-String -Pattern 'href="\d+.\d+.\d+/' ^
\| ForEach { \$*.Matches.Groups\[0].Value.TrimEnd('/') } ^
\| Sort-Object {\[version]\$*} ^
\| Select-Object -Last 1; ^
\$url = '[https://www.python.org/ftp/python/](https://www.python.org/ftp/python/)' + \$v + '/python-' + \$v + '-amd64.exe'; ^
(New-Object Net.WebClient).DownloadFile(\$url,'%PY\_EXEC%')"
if exist "%PY\_EXEC%" (
echo \[INFO] Installation de Python... >> "%LOG\_FILE%"
"%PY\_EXEC%" /quiet InstallAllUsers=1 PrependPath=1 >> "%LOG\_FILE%" 2>&1
if !ERRORLEVEL! EQU 0 (
echo \[OK] Python installé.
echo Python: OK >> "%LOG\_FILE%"
set "STATUS\_PY=✅"
) else (
echo \[ERROR] Échec de l'installation de Python.
echo Python: FAIL >> "%LOG\_FILE%"
set "STATUS\_PY=❌"
)
) else (
echo \[ERROR] Échec du téléchargement de Python.
echo Python: FAIL >> "%LOG\_FILE%"
set "STATUS\_PY=❌"
)
)

if "%STATUS\_PY%"=="✅" (
echo \[INFO] Installation de magic-wormhole via pip... >> "%LOG\_FILE%"
pip install magic-wormhole >> "%LOG\_FILE%" 2>&1
pip show magic-wormhole >nul 2>&1
if !ERRORLEVEL! EQU 0 (
echo \[OK] magic-wormhole installé.
echo magic-wormhole: OK >> "%LOG\_FILE%"
set "STATUS\_WORM=✅"
) else (
echo \[ERROR] Échec de l'installation de magic-wormhole.
echo magic-wormhole: FAIL >> "%LOG\_FILE%"
set "STATUS\_WORM=❌"
)
) else (
set "STATUS\_WORM=🔹"
)

\:: ----------------------------------------
\:: 2) ClamWin Antivirus
echo.
echo ===== ClamWin Antivirus =====
reg query "HKLM\Software\ClamWin" >nul 2>&1
if !ERRORLEVEL! EQU 0 (
echo \[SKIP] ClamWin déjà installé.
echo ClamWin: Déjà installé >> "%LOG\_FILE%"
set "STATUS\_CLAM=🔁"
) else (
set "CLAM\_EXEC=%INSTALL\_DIR%\clamwin-setup.exe"
call \:DownloadAndCheck "[https://downloads.sourceforge.net/project/clamwin/clamwin/1.1.0.1/clamwin-1.1.0.1-setup.exe](https://downloads.sourceforge.net/project/clamwin/clamwin/1.1.0.1/clamwin-1.1.0.1-setup.exe)" "%CLAM\_EXEC%"
if "%LAST\_STATUS%"=="OK" (
echo \[INFO] Installation de ClamWin... >> "%LOG\_FILE%"
"%CLAM\_EXEC%" /silent >> "%LOG\_FILE%" 2>&1
if !ERRORLEVEL! EQU 0 (
echo \[OK] ClamWin installé.
echo ClamWin: OK >> "%LOG\_FILE%"
set "STATUS\_CLAM=✅"
) else (
echo \[ERROR] Échec de l'installation de ClamWin.
echo ClamWin: FAIL >> "%LOG\_FILE%"
set "STATUS\_CLAM=❌"
)
) else (
set "STATUS\_CLAM=❌"
)
)

\:: ----------------------------------------
\:: 3) 7-Zip
echo.
echo ===== 7-Zip =====
where 7z >nul 2>&1
if !ERRORLEVEL! EQU 0 (
echo \[SKIP] 7-Zip déjà installé.
echo 7-Zip: Déjà installé >> "%LOG\_FILE%"
set "STATUS\_7Z=🔁"
) else (
set "ZIP\_EXEC=%INSTALL\_DIR%\7z.exe"
echo \[INFO] Récupération de la dernière version de 7-Zip...
powershell -Command ^
"\$u=(Invoke-WebRequest '[https://www.7-zip.org/](https://www.7-zip.org/)' -UseBasicParsing).Links ^
\| Where-Object { $\_.href -match '7z\d+-x64.exe' } ^
\| Select-Object -First 1 -ExpandProperty href; ^
(New-Object Net.WebClient).DownloadFile(\$u,'%ZIP\_EXEC%')"
if exist "%ZIP\_EXEC%" (
echo \[INFO] Installation de 7-Zip... >> "%LOG\_FILE%"
start /wait "%ZIP\_EXEC%" /S >> "%LOG\_FILE%" 2>&1
if !ERRORLEVEL! EQU 0 (
echo \[OK] 7-Zip installé.
echo 7-Zip: OK >> "%LOG\_FILE%"
set "STATUS\_7Z=✅"
) else (
echo \[ERROR] Échec de l'installation de 7-Zip.
echo 7-Zip: FAIL >> "%LOG\_FILE%"
set "STATUS\_7Z=❌"
)
) else (
echo \[ERROR] Échec du téléchargement de 7-Zip.
echo 7-Zip: FAIL >> "%LOG\_FILE%"
set "STATUS\_7Z=❌"
)
)

\:: ----------------------------------------
\:: 4) RustDesk
echo.
echo ===== RustDesk =====
reg query "HKLM\Software\RustDesk" >nul 2>&1
if !ERRORLEVEL! EQU 0 (
echo \[SKIP] RustDesk déjà installé.
echo RustDesk: Déjà installé >> "%LOG\_FILE%"
set "STATUS\_RUST=🔁"
) else (
set "RUST\_BASE=%INSTALL\_DIR%\rustdesk"
mkdir "%RUST\_BASE%" >nul 2>&1
echo \[INFO] Récupération de la dernière version de RustDesk...
powershell -Command ^
"\$j = Invoke-RestMethod -UseBasicParsing '[https://api.github.com/repos/rustdesk/rustdesk/releases/latest](https://api.github.com/repos/rustdesk/rustdesk/releases/latest)'; ^
\$asset = \$j.assets ^
\| Where-Object { $\_.name -match 'rustdesk-.*.(msi|exe)\$' } ^
\| Select-Object -First 1; ^
(New-Object Net.WebClient).DownloadFile(\$asset.browser\_download\_url,
'%RUST\_BASE%' + \$asset.name)"
for %%F in (exe msi) do if exist "%RUST\_BASE%\rustdesk*.%%F" set "RUST\_FILE=%%F"
if defined RUST\_FILE (
echo \[INFO] Installation de RustDesk... >> "%LOG\_FILE%"
if /I "%RUST\_FILE%"=="msi" (
msiexec /i "%RUST\_BASE%\rustdesk\*.msi" /quiet >> "%LOG\_FILE%" 2>&1
) else (
start /wait "%RUST\_BASE%\rustdesk\*.exe" /S >> "%LOG\_FILE%" 2>&1
)
if !ERRORLEVEL! EQU 0 (
echo \[OK] RustDesk installé.
echo RustDesk: OK >> "%LOG\_FILE%"
set "STATUS\_RUST=✅"
) else (
echo \[ERROR] Échec de l'installation de RustDesk.
echo RustDesk: FAIL >> "%LOG\_FILE%"
set "STATUS\_RUST=❌"
)
) else (
echo \[ERROR] Fichier RustDesk introuvable.
set "STATUS\_RUST=❌"
)
)

\:: ----------------------------------------
\:: Récapitulatif final
echo.
echo ===== Résultat des installations =====
echo Python           %STATUS\_PY%
echo magic-wormhole  %STATUS\_WORM%
echo ClamWin          %STATUS\_CLAM%
echo 7-Zip            %STATUS\_7Z%
echo RustDesk         %STATUS\_RUST%
echo.

set "FINAL\_FAIL=0"
for %%S in (STATUS\_PY STATUS\_WORM STATUS\_CLAM STATUS\_7Z STATUS\_RUST) do (
if "!%%\~S!"=="❌" set "FINAL\_FAIL=1"
)

if !FINAL\_FAIL! EQU 1 (
echo ⚠️ Certaines installations ont échoué. Voir le log : .\install\_log.txt
) else (
echo ✅ Toutes les installations ont réussi.
)

echo.
pause
