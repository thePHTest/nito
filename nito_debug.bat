@echo off
set bat_dir=%~dp0
pushd %bat_dir%
pushd debug_build
call win32_nito.exe
popd
popd