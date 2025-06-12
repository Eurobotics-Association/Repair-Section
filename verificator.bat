@echo off
rem =============================================
rem VERIFICATOR.BAT - Vérifie l'intégrité des archives
rem Version : v.20250612-16.48 / DeepSeek
rem =============================================

rem === Force UTF-8 system-wide ===
chcp 65001 >nul 2>&1
setlocal EnableExtensions EnableDelayedExpansion

rem === Configure console for Unicode ===
if not defined _UNICODE_SET_ (
    set "_UNICODE_SET_=1"
    reg add "HKCU\Console" /v "CodePage" /t REG_DWORD /d 65001 /f >nul
    reg add "HKCU\Console" /v "FaceName" /t REG_SZ /d "Consolas" /f >nul
    reg add "HKCU\Console" /v "FontFamily" /t REG_DWORD /d 0x36 /f >nul
)

rem === ANSI Color Codes ===
set "COLOR_RESET=[0m"
set "COLOR_RED=[91m"
set "COLOR_GREEN=[92m"
set "COLOR_YELLOW=[93m"
set "COLOR_CYAN=[96m"
set "COLOR_WHITE=[97m"

rem === Create UTF-8 log file with BOM ===
set "LOG_FILE=verificator_log.txt"
if exist "%LOG_FILE%" del /f /q "%LOG_FILE%"
echo ÿþ > "%LOG_FILE%" 2>nul

set "OK_COUNT=0"
set "FAIL_COUNT=0"
set "TOTAL_COUNT=0"

rem === Vérification 7z.exe ===
where 7z.exe >nul 2>&1
if %errorlevel% neq 0 (
    if exist "C:\Program Files\7-Zip\7z.exe" (
        set "PATH=C:\Program Files\7-Zip;%PATH%"
        echo %COLOR_CYAN%[INFO] 7-Zip ajouté au PATH%COLOR_RESET%
        echo [INFO] 7-Zip ajouté au PATH >> "%LOG_FILE%"
    ) else (
        echo %COLOR_RED%[ERREUR] 7-Zip manquant: https://www.7-zip.org%COLOR_RESET%
        echo [ERREUR] 7-Zip manquant: https://www.7-zip.org >> "%LOG_FILE%"
        pause
        exit /b 1
    )
)

rem === Début vérification ===
echo %COLOR_WHITE%===== DEBUT VERIFICATION =====%COLOR_RESET%
echo ===== DEBUT VERIFICATION ===== >> "%LOG_FILE%"
echo/

for %%F in (*.zip *.7z *.7z.001) do (
    echo %%F | findstr /r /c:"\.7z\.00[2-9]$" >nul
    if !errorlevel! equ 0 (
        echo %COLOR_YELLOW%[INFO] Ignoré: %%F%COLOR_RESET%
        echo [INFO] Ignoré: %%F >> "%LOG_FILE%"
    ) else (
        echo %COLOR_CYAN%[INFO] Vérification: %%F%COLOR_RESET%
        echo [INFO] Vérification: %%F >> "%LOG_FILE%"
        set /a TOTAL_COUNT+=1
        
        rem === Force UTF-8 output from 7z ===
        cmd /u /c "7z.exe t "%%F" 2>&1" >> "%LOG_FILE%"
        
        if !errorlevel! neq 0 (
            echo %COLOR_RED%[ERREUR] Corrompu: %%F%COLOR_RESET%
            echo [ERREUR] Corrompu: %%F >> "%LOG_FILE%"
            set /a FAIL_COUNT+=1
        ) else (
            echo %COLOR_GREEN%[OK] Valide: %%F%COLOR_RESET%
            echo [OK] Valide: %%F >> "%LOG_FILE%"
            set /a OK_COUNT+=1
        )
        echo/ >> "%LOG_FILE%"
    )
)

rem === Récapitulatif ===
echo/
echo %COLOR_CYAN%===== RAPPORT VERIFICATION =====%COLOR_RESET%
echo Total: %TOTAL_COUNT% fichier(s)
echo %COLOR_GREEN%Valides: %OK_COUNT%%COLOR_RESET%
echo %COLOR_RED%Corrompus: %FAIL_COUNT%%COLOR_RESET%
echo %COLOR_WHITE%Détails: "%LOG_FILE%"%COLOR_RESET%
echo/
echo %COLOR_YELLOW%VÉRIFICATION TERMINÉE AVEC SUCCÈS%COLOR_RESET%
echo Appuyez sur une touche pour quitter...
pause >nul
endlocal
exit /b 0
