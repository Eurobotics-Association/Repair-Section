@echo on

:: =============================================
:: VERIFICATOR.BAT - Vérifie l'intégrité des fichiers .zip et .7z dans le dossier courant
:: Compatible Windows 7, 10, 11
:: =============================================

:: === Variables globales ===
setlocal EnableExtensions EnableDelayedExpansion
set "CURDIR=%CD%"
set "LOG_FILE=%CURDIR%\verificator_log.txt"
if exist "%LOG_FILE%" del /f /q "%LOG_FILE%"

set "OK_COUNT=0"
set "FAIL_COUNT=0"
set "TOTAL_COUNT=0"

:: === Vérification de la présence de 7z.exe ===
where 7z.exe >nul 2>&1
if %errorlevel% neq 0 (
    if exist "C:\Program Files\7-Zip\7z.exe" (
        set "PATH=C:\Program Files\7-Zip;%PATH%"
        echo [INFO] 7-Zip ajouté au PATH depuis C:\Program Files\7-Zip
    ) else (
        echo [ERREUR] 7-Zip non détecté. Veuillez l'installer depuis https://www.7-zip.org
        pause
        exit /b 1
    )
)

:: === Début de la vérification ===
echo ===== DEBUT DE VERIFICATION ===== >> "%LOG_FILE%"
echo.
for %%F in (*.7z *.zip) do (
    echo [INFO] Vérification : %%F
    echo [INFO] Vérification : %%F >> "%LOG_FILE%"
    set /a TOTAL_COUNT+=1
    7z.exe t "%%F" >> "%LOG_FILE%" 2>&1
    if !errorlevel! neq 0 (
        echo [ERREUR] Archive corrompue : %%F
        echo [ERREUR] Archive corrompue : %%F >> "%LOG_FILE%"
        set /a FAIL_COUNT+=1
    ) else (
        echo [OK] Archive valide : %%F
        echo [OK] Archive valide : %%F >> "%LOG_FILE%"
        set /a OK_COUNT+=1
    )
    echo. >> "%LOG_FILE%"
)

:: === Récapitulatif final ===
echo.
echo ===== RAPPORT DE VERIFICATION =====
echo Total : %TOTAL_COUNT% fichier(s) vérifié(s)
echo Succès : %OK_COUNT%
echo Échecs : %FAIL_COUNT%
echo Voir "%LOG_FILE%" pour les détails complets.
echo.
echo Appuyez sur une touche pour quitter...
pause >nul
endlocal
exit /b 0
