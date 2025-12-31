#!/usr/bin/env pwsh
# Configure bindgen compatibility headers for Windows
# Used by: ci-ruby.yaml - Configure bindgen compatibility headers step

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "=== Configuring bindgen compatibility headers for Windows ===" -ForegroundColor Cyan

$includeRoot = "$env:GITHUB_WORKSPACE\packages\ruby\ext\kreuzberg_rb\native\include"
$compat = "$includeRoot\msvc_compat"
$includeRoot = $includeRoot -replace '\\','/'
$compatForward = $compat -replace '\\','/'

# Build the extra clang args with all necessary paths and flags
$extra = "-I$includeRoot -I$compatForward -fms-extensions -fstack-protector-strong -fno-omit-frame-pointer -fno-fast-math"

# Check for MSYS2/MinGW sysroot
if ($env:MSYSTEM_PREFIX) {
    $sysroot = "$env:MSYSTEM_PREFIX" -replace '\\','/'
    $extra += " --target=x86_64-pc-windows-gnu --sysroot=$sysroot"
    Write-Host "MSYS2 detected: Using sysroot $sysroot"
}

# Set for all possible target formats (bindgen uses different naming conventions)
Add-Content -Path $env:GITHUB_ENV -Value "BINDGEN_EXTRA_CLANG_ARGS=$extra"
Add-Content -Path $env:GITHUB_ENV -Value "BINDGEN_EXTRA_CLANG_ARGS_x86_64-pc-windows-msvc=$extra"
Add-Content -Path $env:GITHUB_ENV -Value "BINDGEN_EXTRA_CLANG_ARGS_x86_64_pc_windows_msvc=$extra"
Add-Content -Path $env:GITHUB_ENV -Value "BINDGEN_EXTRA_CLANG_ARGS_x86_64-pc-windows-gnu=$extra"
Add-Content -Path $env:GITHUB_ENV -Value "BINDGEN_EXTRA_CLANG_ARGS_x86_64_pc_windows_gnu=$extra"

Write-Host "BINDGEN_EXTRA_CLANG_ARGS set to: $extra"
Write-Host "Configuration complete" -ForegroundColor Green
