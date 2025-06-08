@echo on

:: =============================================
:: INITIATOR.BAT - Outil d'installation automatisée
:: Compatible Windows 7, 10, 11 - Exécution PowerShell Admin requise
:: =============================================

:: === Vérification des droits administrateur ===
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERREUR] Ce script doit être lancé en tant qu'administrateur.
    pause
    exit /b 1
)

:: === Vérification si exécuté dans PowerShell ===
where powershell >nul 2>&1 || (
    echo [ERREUR] PowerShell non disponible.
    pause
    exit /b 1
)

:: === Définition des symboles compatibles Win7 ===
set "OK=[OK]"
set "FAIL=[ERREUR]"
set "SKIP=[DÉJÀ INSTALLE]"

setlocal enableextensions enabledelayedexpansion

:: === Variables globales ===
set "CURDIR=%CD%"
set "INSTALL_DIR=%CD%\installers"
set "LOG_FILE=%CD%\install_log.txt"

:: === Nettoyage & Préparation ===
if not exist "%INSTALL_DIR%" mkdir "%INSTALL_DIR%"
if exist "%LOG_FILE%" del /f /q "%LOG_FILE%"
echo === Lancement de l'installation... === > "%LOG_FILE%"

:: === Vérifier l'espace disque disponible ===
for /f %%f in ('powershell -NoProfile -Command "(Get-PSDrive -Name $env:SystemDrive[0]).Free"') do set "FreeSpace=%%f"
if not defined FreeSpace set "FreeSpace=0"
echo Espace libre détecté : %FreeSpace% octets
if %FreeSpace% LSS 1000000000 (
    echo [ERREUR] Moins de 1 Go d'espace libre. >> "%LOG_FILE%"
    echo [ERREUR] Moins de 1 Go d'espace libre.
    exit /b 1
)

:: === Vérifier la connexion Internet ===
ping -n 2 8.8.8.8 >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERREUR] Aucune connexion Internet détectée. >> "%LOG_FILE%"
    echo [ERREUR] Aucune connexion Internet détectée.
    exit /b 1
)
echo Connexion Internet détectée.

:: === Étape 1 : Python + pip ===
call :IsInstalled python.exe
if %errorlevel%==2 goto python_done
set PYTHON_URL=https://www.python.org/ftp/python/3.10.11/python-3.10.11-amd64.exe
set PYTHON_EXE=%INSTALL_DIR%\python_installer.exe
powershell -NoProfile -Command "Try { (New-Object System.Net.WebClient).DownloadFile('%PYTHON_URL%', '%PYTHON_EXE%') } Catch { Exit 1 }"
if not exist "%PYTHON_EXE%" (
    echo !FAIL! Python téléchargement échoué >> "%LOG_FILE%"
    echo !FAIL! Python téléchargement échoué
    exit /b 1
)
%PYTHON_EXE% /quiet InstallAllUsers=1 PrependPath=1 Include_pip=1
if %errorlevel% neq 0 (
    echo !FAIL! Python installation échouée >> "%LOG_FILE%"
    echo !FAIL! Python installation échouée
) else (
    echo !OK! Python installé >> "%LOG_FILE%"
    echo !OK! Python installé
)
:python_done

:: === Étape 2 : magic-wormhole ===
call :IsInstalled pip.exe
if %errorlevel%==2 goto wormhole_done
pip show magic-wormhole >nul 2>&1
if %errorlevel%==0 (
    echo !SKIP! magic-wormhole déjà installé. >> "%LOG_FILE%"
    echo !SKIP! magic-wormhole déjà installé.
    goto wormhole_done
)
pip install magic-wormhole
if %errorlevel% neq 0 (
    echo !FAIL! magic-wormhole installation échouée >> "%LOG_FILE%"
    echo !FAIL! magic-wormhole installation échouée
) else (
    echo !OK! magic-wormhole installé >> "%LOG_FILE%"
    echo !OK! magic-wormhole installé
)
:wormhole_done

:: === Étape 3 : ClamWin Antivirus ===
call :IsInstalled ClamWin.exe
if %errorlevel%==2 goto clam_done
set CLAM_URL=https://downloads.sourceforge.net/project/clamwin/clamwin/0.103.2/clamwin-0.103.2-setup.exe
set CLAM_EXE=%INSTALL_DIR%\clamwin_installer.exe
powershell -NoProfile -Command "Try { (New-Object System.Net.WebClient).DownloadFile('%CLAM_URL%', '%CLAM_EXE%') } Catch { Exit 1 }"
if not exist "%CLAM_EXE%" (
    echo !FAIL! Échec du téléchargement de ClamWin >> "%LOG_FILE%"
    echo !FAIL! Échec du téléchargement de ClamWin
    exit /b 1
)
%CLAM_EXE% /SP- /VERYSILENT /NORESTART
if %errorlevel% neq 0 (
    echo !FAIL! ClamWin installation échouée >> "%LOG_FILE%"
    echo !FAIL! ClamWin installation échouée
) else (
    echo !OK! ClamWin installé >> "%LOG_FILE%"
    echo !OK! ClamWin installé
)
:clam_done

:: === Étape 4 : 7-Zip ===
call :IsInstalled 7z.exe
if %errorlevel%==2 goto zip_done
set ZIP_URL=https://www.7-zip.org/a/7z2401-x64.exe
set ZIP_EXE=%INSTALL_DIR%\7zip_installer.exe
powershell -NoProfile -Command "Try { (New-Object System.Net.WebClient).DownloadFile('%ZIP_URL%', '%ZIP_EXE%') } Catch { Exit 1 }"
if not exist "%ZIP_EXE%" (
    echo !FAIL! Échec du téléchargement de 7-Zip >> "%LOG_FILE%"
    echo !FAIL! Échec du téléchargement de 7-Zip
    exit /b 1
)
%ZIP_EXE% /S
if %errorlevel% neq 0 (
    echo !FAIL! 7-Zip installation échouée >> "%LOG_FILE%"
    echo !FAIL! 7-Zip installation échouée
) else (
    echo !OK! 7-Zip installé >> "%LOG_FILE%"
    echo !OK! 7-Zip installé
)
:zip_done

:: === Étape 5 : RustDesk ===
call :IsInstalled rustdesk.exe
if %errorlevel%==2 goto rust_done
:: Vérifie si rustdesk est en cours d'exécution
powershell -Command "Get-Process rustdesk -ErrorAction SilentlyContinue" >nul 2>&1
if %errorlevel%==0 (
    echo !FAIL! RustDesk est en cours d'exécution, fermeture nécessaire avant installation >> "%LOG_FILE%"
    echo !FAIL! RustDesk est en cours d'exécution, fermeture nécessaire avant installation
    exit /b 1
)
set RUST_URL=https://github.com/rustdesk/rustdesk/releases/download/1.2.3/rustdesk-1.2.3-windows_x64.exe
set RUST_EXE=%INSTALL_DIR%\rustdesk_installer.exe
powershell -NoProfile -Command "Try { (New-Object System.Net.WebClient).DownloadFile('%RUST_URL%', '%RUST_EXE%') } Catch { Exit 1 }"
if not exist "%RUST_EXE%" (
    echo !FAIL! Échec du téléchargement de RustDesk >> "%LOG_FILE%"
    echo !FAIL! Échec du téléchargement de RustDesk
    exit /b 1
)
%RUST_EXE% /SILENT
if %errorlevel% neq 0 (
    echo !FAIL! RustDesk installation échouée >> "%LOG_FILE%"
    echo !FAIL! RustDesk installation échouée
) else (
    echo !OK! RustDesk installé >> "%LOG_FILE%"
    echo !OK! RustDesk installé
)
:rust_done

:: === Résumé final ===
echo.
echo ========= ✅ RÉCAPITULATIF =========
echo Voir le fichier .\install_log.txt pour plus de détails.
echo ====================================

findstr /R "\[OK\] \[ERREUR\] \[DÉJÀ INSTALLE\]" "%LOG_FILE%"

findstr /C:"[ERREUR]" "%LOG_FILE%" >nul
if %errorlevel%==0 echo ⚠️ Certaines installations ont échoué. Voir le log ici : .\install_log.txt

:: === Fonction : Vérifie si un programme est déjà installé (basique) ===
:IsInstalled
:: %1 = nom de fichier, ex: python.exe
if "%~1"=="" (
    echo [ERREUR] Appel incorrect de :IsInstalled sans argument. >> "%LOG_FILE%"
    echo [ERREUR] Appel incorrect de :IsInstalled sans argument.
    exit /b 1
)
where %1 >nul 2>&1
if %errorlevel%==0 (
    echo !SKIP! %1 déjà installé. >> "%LOG_FILE%"
    echo !SKIP! %1 déjà installé.
    exit /b 2
)
echo !OK! %1 n'est pas installé.
exit /b 0

endlocal
exit /b 0
