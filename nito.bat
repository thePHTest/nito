@echo off
set bat_dir=%~dp0
pushd %bat_dir%
pushd build
call win32_nito.exe
popd
popd