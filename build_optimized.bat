@echo off
echo Building optimized APK...

REM Clean previous builds
echo Cleaning previous builds...
flutter clean

REM Get dependencies
echo Getting dependencies...
flutter pub get

REM Build optimized APK
echo Building release APK with optimizations...
flutter build apk --release --shrink --split-per-abi --target-platform android-arm64

REM Check if build was successful
if exist "build\app\outputs\flutter-apk\app-arm64-v8a-release.apk" (
    echo.
    echo ====================================
    echo BUILD SUCCESSFUL!
    echo ====================================
    echo.
    echo APK Location: build\app\outputs\flutter-apk\
    echo.
    echo APK files created:
    dir "build\app\outputs\flutter-apk\*.apk" /b
    echo.
    echo File sizes:
    for %%f in ("build\app\outputs\flutter-apk\*.apk") do (
        echo %%~nf: %%~zf bytes
    )
) else (
    echo.
    echo BUILD FAILED!
    echo Please check the output above for errors.
)

echo.
echo Press any key to continue...
pause > nul
