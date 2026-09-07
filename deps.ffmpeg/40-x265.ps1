param(
    [string] $Name = 'x265',
    [string] $Version = '4.3',
    [string] $Uri = 'https://github.com/multicorewareinc/x265.git',
    [string] $Hash = 'e9b88125dc21393b3fd8d68e98083bdfb89778a8',
    [array] $Targets = @('x64'),
    [switch] $ForceShared = $true
)

function Setup {
    Setup-Dependency -Uri $Uri -Hash $Hash -DestinationPath $Path
}

function Patch {
    Log-Information "Patch (${Target})"
    Set-Location $Path

    # Apply whole-archive patch inline (avoids line-ending issues with patch files on Windows)
    $CMakeFile = "source/CMakeLists.txt"
    $content = Get-Content $CMakeFile -Raw

    $oldText = @'
    if(EXTRA_LIB)
        target_link_libraries(x265-shared ${EXTRA_LIB})
    endif()
'@

    $newText = @'
    if(EXTRA_LIB_DIR10 OR EXTRA_LIB_DIR12)
        # Resolve satellite static library paths and link with whole-archive
        if(MSVC)
            # For MSVC: copy satellite libs into build dir with unique names,
            # then reference by basename to avoid VS generator path mangling.
            if(EXTRA_LIB_DIR10)
                get_filename_component(_abs_lib_10 "${EXTRA_LIB_DIR10}/Release/x265-static.lib" ABSOLUTE)
                add_custom_command(TARGET x265-shared PRE_LINK
                    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${_abs_lib_10}" "${CMAKE_CURRENT_BINARY_DIR}/x265-10bit.lib"
                    COMMENT "Copying 10-bit satellite lib"
                )
                list(APPEND LINKER_OPTIONS "/WHOLEARCHIVE:x265-10bit.lib")
            endif()
            if(EXTRA_LIB_DIR12)
                get_filename_component(_abs_lib_12 "${EXTRA_LIB_DIR12}/Release/x265-static.lib" ABSOLUTE)
                add_custom_command(TARGET x265-shared PRE_LINK
                    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${_abs_lib_12}" "${CMAKE_CURRENT_BINARY_DIR}/x265-12bit.lib"
                    COMMENT "Copying 12-bit satellite lib"
                )
                list(APPEND LINKER_OPTIONS "/WHOLEARCHIVE:x265-12bit.lib")
            endif()
        else()
            # Non-MSVC: use absolute paths directly (force_load / whole-archive handle them fine)
            if(EXTRA_LIB_DIR10)
                set(_satellite_lib_10 "${EXTRA_LIB_DIR10}/libx265.a")
            endif()
            if(EXTRA_LIB_DIR12)
                set(_satellite_lib_12 "${EXTRA_LIB_DIR12}/libx265.a")
            endif()

            set(_satellite_libs "")
            if(_satellite_lib_10)
                list(APPEND _satellite_libs "${_satellite_lib_10}")
            endif()
            if(_satellite_lib_12)
                list(APPEND _satellite_libs "${_satellite_lib_12}")
            endif()

            if(APPLE)
                foreach(_extra_lib ${_satellite_libs})
                    list(APPEND LINKER_OPTIONS "-Wl,-force_load,${_extra_lib}")
                endforeach()
            else()
                list(APPEND LINKER_OPTIONS "-Wl,--whole-archive")
                list(APPEND LINKER_OPTIONS ${_satellite_libs})
                list(APPEND LINKER_OPTIONS "-Wl,--no-whole-archive")
            endif()
        endif()
    endif()
'@

    if ($content -match [regex]::Escape($oldText)) {
        $content = $content.Replace($oldText, $newText)
        Set-Content -Path $CMakeFile -Value $content -NoNewline
        Log-Information "Applied whole-archive patch to CMakeLists.txt"
    } else {
        # Try with normalized line endings
        $oldNorm = $oldText -replace "`r`n", "`n"
        $newNorm = $newText -replace "`r`n", "`n"
        $contentNorm = $content -replace "`r`n", "`n"
        if ($contentNorm -match [regex]::Escape($oldNorm)) {
            $contentNorm = $contentNorm.Replace($oldNorm, $newNorm)
            Set-Content -Path $CMakeFile -Value $contentNorm -NoNewline
            Log-Information "Applied whole-archive patch to CMakeLists.txt (normalized)"
        } else {
            Log-Warning "Could not find pattern to patch in CMakeLists.txt - skipping"
        }
    }
}

function Clean {
    Set-Location $Path
    foreach ( $Dir in @("build_${Target}", "build_10bit_${Target}", "build_12bit_${Target}") ) {
        if ( Test-Path $Dir ) {
            Log-Information "Clean build directory (${Dir})"
            Remove-Item -Path $Dir -Recurse -Force
        }
    }
}

function Configure {
    Log-Information "Configure (${Target})"
    Set-Location $Path

    if ( $ForceShared -and ( $script:Shared -eq $false ) ) {
        $Shared = $true
    } else {
        $Shared = $script:Shared.isPresent
    }

    $OnOff = @('OFF', 'ON')
    $CommonOptions = @(
        $CmakeOptions
        '-DENABLE_CLI:BOOL=OFF'
        '-DENABLE_TESTING:BOOL=OFF'
        '-DCMAKE_POSITION_INDEPENDENT_CODE:BOOL=ON'
    )

    # 10-bit static library (namespaced symbols, no C API export)
    Log-Information "Configure x265 10-bit static (${Target})"
    $Options10 = @(
        $CommonOptions
        '-DBUILD_SHARED_LIBS:BOOL=OFF'
        '-DENABLE_SHARED:BOOL=OFF'
        '-DHIGH_BIT_DEPTH:BOOL=ON'
        '-DEXPORT_C_API:BOOL=OFF'
    )
    Invoke-External cmake -S source -B "build_10bit_${Target}" @Options10

    # 12-bit static library (namespaced symbols, no C API export)
    Log-Information "Configure x265 12-bit static (${Target})"
    $Options12 = @(
        $CommonOptions
        '-DBUILD_SHARED_LIBS:BOOL=OFF'
        '-DENABLE_SHARED:BOOL=OFF'
        '-DHIGH_BIT_DEPTH:BOOL=ON'
        '-DMAIN12:BOOL=ON'
        '-DEXPORT_C_API:BOOL=OFF'
    )
    Invoke-External cmake -S source -B "build_12bit_${Target}" @Options12

    # Main shared library (8-bit C API + linked 10/12-bit for x265_api_get dispatch)
    Log-Information "Configure x265 main shared (${Target})"
    $cwd = (Get-Location).ProviderPath

    $OptionsMain = @(
        $CommonOptions
        "-DBUILD_SHARED_LIBS:BOOL=$($OnOff[$Shared])"
        '-DEXTRA_LIB=1'
        "-DEXTRA_LIB_DIR10=${cwd}/build_10bit_${Target}"
        "-DEXTRA_LIB_DIR12=${cwd}/build_12bit_${Target}"
        '-DLINKED_10BIT:BOOL=ON'
        '-DLINKED_12BIT:BOOL=ON'
    )
    Invoke-External cmake -S source -B "build_${Target}" @OptionsMain
}

function Build {
    Log-Information "Build (${Target})"
    Set-Location $Path

    $CommonBuildOpts = @('--config', $Configuration)
    if ( $VerbosePreference -eq 'Continue' ) {
        $CommonBuildOpts += '--verbose'
    }

    # Build 10-bit static first
    Log-Information "Build x265 10-bit static (${Target})"
    Invoke-External cmake --build "build_10bit_${Target}" @CommonBuildOpts

    # Build 12-bit static second
    Log-Information "Build x265 12-bit static (${Target})"
    Invoke-External cmake --build "build_12bit_${Target}" @CommonBuildOpts

    # Build main shared last (links against the other two)
    Log-Information "Build x265 main shared (${Target})"
    Invoke-External cmake --build "build_${Target}" @CommonBuildOpts
}

function Install {
    Log-Information "Install (${Target})"
    Set-Location $Path

    $Options = @(
        '--install', "build_${Target}"
        '--config', $Configuration
    )

    if ( $Configuration -match "(Release|MinSizeRel)" ) {
        $Options += '--strip'
    }

    Invoke-External cmake @Options
}

function Fixup {
    Log-Information "Fixup (${Target})"
    Set-Location $Path

    if ( $ForceShared -and ( $script:Shared -eq $false ) ) {
        $Shared = $true
    } else {
        $Shared = $script:Shared.isPresent
    }

    if ( $Shared ) {
        # Ensure import library is named correctly for FFmpeg's pkg-config detection
        if ( Test-Path "$($script:ConfigData.OutputPath)/lib/x265.lib" ) {
            Log-Debug "Import library already correctly named: x265.lib"
        } elseif ( Test-Path "$($script:ConfigData.OutputPath)/lib/libx265.lib" ) {
            Rename-Item "$($script:ConfigData.OutputPath)/lib/libx265.lib" -NewName "x265.lib"
        }
    }
}
