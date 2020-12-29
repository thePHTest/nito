@echo off
set bat_dir=%~dp0
pushd %bat_dir%
IF NOT EXIST .\build mkdir .\build
pushd build
odin build ../src/win32_nito.odin
popd popd
