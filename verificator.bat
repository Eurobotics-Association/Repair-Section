@echo off
rem =============================================
rem VERIFICATOR.BAT - Vérifie l'intégrité des archives
rem Version : v.20250613-16.15
rem =============================================

rem === Fix encoding system-wide ===
chcp 65001 >nul 2>&1
setlocal EnableExtensions EnableDelayedExpansion

rem === ANSI Color Codes ===
for /F "tokens=1,2 delims=#" %%a in ('"prompt #$H#$E# & echo on & for %%b in (1) do rem"') do (
  set "ANSI_ESC=%%b"
)
set "COLOR_RESET=%ANSI_ESC%[0m"
set "COLOR_RED=%ANSI_ESC%[91m"
set "COLOR_GREEN=%ANSI_ESC%[92m"
set "COLOR_YELLOW=%ANSI_ESC%[93m"
set "COLOR_CYAN=%ANSI_ESC%[96m"

rem === Create log file with UTF-8 BOM ===
set "LOG_FILE=verificator_log.txt"
if exist "%LOG_FILE%" del /f /q "%LOG_FILE%"
echo ÿþ > "%LOG_FILE%" 2>nul & rem (UTF-8 BOM marker)

set "OK_COUNT=0"
set "FAIL_COUNT=0"
set "TOTAL_COUNT=0"

rem === Vérification 7z.exe ===
where 7z.exe >nul 2>&1
if %errorlevel% neq 0 (
    if exist "C:\Program Files\7-Zip\7z.exe" (
        set "PATH=C:\Program Files\7-Zip;%PATH%"
        echo [INFO] 7-Zip ajouté au PATH
    ) else (
        echo %COLOR_RED%[ERREUR] 7-Zip manquant: https://www.7-zip.org%COLOR_RESET%
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
        echo %COLOR_YELLOW%[INFO] Ignoré: %%F%COLOR_RESET%
        echo [INFO] Ignoré: %%F >> "%LOG_FILE%"
    ) else (
        echo %COLOR_CYAN%[INFO] Vérification: %%F%COLOR_RESET%
        echo [INFO] Vérification: %%F >> "%LOG_FILE%"
        set /a TOTAL_COUNT+=1
        7z.exe t "%%F" >> "%LOG_FILE%" 2>&1
        if !errorlevel! neq 0 (
            echo %COLOR_RED%[ERREUR] Corrompu: %%F%COLOR_RESET%
            echo [ERREUR] Corrompu: %%F >> "%LOG_FILE%"
            set /a FAIL_COUNT+=1
        ) else (
            echo %COLOR_GREEN%[OK] Valide: %%F%COLOR_RESET%
            echo [OK] Valide: %%F >> "%LOG_FILE%"
            set /a OK_COUNT+=1
        )
        echo; >> "%LOG_FILE%"
    )
)

rem === Récapitulatif ===
echo;
echo %COLOR_CYAN%===== RAPPORT VERIFICATION =====%COLOR_RESET%
echo Total: %TOTAL_COUNT% fichier(s)
echo %COLOR_GREEN%Valides: %OK_COUNT%%COLOR_RESET%
echo %COLOR_RED%Corrompus: %FAIL_COUNT%%COLOR_RESET%
echo Détails: "%LOG_FILE%"
echo;
echo %COLOR_YELLOW%VÉRIFICATION TERMINÉE AVEC SUCCÈS%COLOR_RESET%
echo Appuyez sur une touche pour quitter...
pause >nul
endlocal
exit /b 0
