@echo off
chcp 65001 >nul 2>&1
setlocal EnableExtensions EnableDelayedExpansion

rem =============================================
rem VERIFICATOR.BAT - Vérifie l'intégrité des archives
rem Version : v.20250613-00.42
rem =============================================

set "LOG_FILE=verificator_log.txt"
if exist "%LOG_FILE%" del /f /q "%LOG_FILE%"

set "OK_COUNT=0"
set "FAIL_COUNT=0"
set "TOTAL_COUNT=0"

rem === Tags de statut ===
set "TAG_OK=OK"
set "TAG_ERR=ERREUR"
set "TAG_INFO=INFO"

rem === Vérification 7z.exe ===
where 7z.exe >nul 2>&1
if %errorlevel% neq 0 (
    if exist "C:\Program Files\7-Zip\7z.exe" (
        set "PATH=C:\Program Files\7-Zip;%PATH%"
        echo [%TAG_INFO%] 7-Zip ajouté au PATH
    ) else (
        echo [%TAG_ERR%] 7-Zip manquant: https://www.7-zip.org
        pause
        exit /b 1
    )
)

rem === Début vérification ===
(
    echo ===== DEBUT VERIFICATION =====
    echo;
) >> "%LOG_FILE%"

for %%F in (*.zip *.7z *.7z.001) do (
    echo %%F | findstr /r /c:"\.7z\.00[2-9]$" >nul
    if !errorlevel! equ 0 (
        echo [%TAG_INFO%] Ignoré: %%F
        echo [%TAG_INFO%] Ignoré: %%F >> "%LOG_FILE%"
    ) else (
        echo [%TAG_INFO%] Vérification: %%F
        echo [%TAG_INFO%] Vérification: %%F >> "%LOG_FILE%"
        set /a TOTAL_COUNT+=1
        7z.exe t "%%F" >> "%LOG_FILE%" 2>&1
        if !errorlevel! neq 0 (
            echo [%TAG_ERR%] Corrompu: %%F
            echo [%TAG_ERR%] Corrompu: %%F >> "%LOG_FILE%"
            set /a FAIL_COUNT+=1
        ) else (
            echo [%TAG_OK%] Valide: %%F
            echo [%TAG_OK%] Valide: %%F >> "%LOG_FILE%"
            set /a OK_COUNT+=1
        )
        echo; >> "%LOG_FILE%"
    )
)

rem === Récapitulatif ===
echo;
echo ===== RAPPORT VERIFICATION =====
echo Total: %TOTAL_COUNT% fichier(s)
echo Valides: %OK_COUNT%
echo Corrompus: %FAIL_COUNT%
echo Détails: "%LOG_FILE%"
echo;
pause >nul
endlocal
exit /b 0
