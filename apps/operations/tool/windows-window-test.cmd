@echo off
setlocal
rem Run from a VS x64 Native Tools prompt, in the prepared Flutter project.
rem flutter build windows must have populated windows\flutter\ephemeral first.
if not exist windows\flutter\ephemeral\flutter_windows.dll exit /b 1
if not exist build\window-tests mkdir build\window-tests
for %%P in (pos manager) do (
  call :test %%P
  if errorlevel 1 exit /b 1
)
exit /b 0
:test
set "DEFINES="
if "%1"=="pos" set "DEFINES=/DVYNIC_POS_FULLSCREEN"
cl /nologo /EHsc /std:c++17 /W4 /WX /wd4100 /DUNICODE /D_UNICODE /DNOMINMAX %DEFINES% /Iwindows\runner /Iwindows\flutter\ephemeral windows\tests\fullscreen_smoke.cpp windows\runner\win32_window.cpp /Fobuild\window-tests\ /Febuild\window-tests\%1.exe /link windows\flutter\ephemeral\flutter_windows.dll.lib dwmapi.lib user32.lib advapi32.lib
if errorlevel 1 exit /b 1
copy /Y windows\flutter\ephemeral\flutter_windows.dll build\window-tests\ >nul
build\window-tests\%1.exe
exit /b %ERRORLEVEL%
