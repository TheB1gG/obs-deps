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

function Clean {
    Set-Location $Path
    if ( Test-Path "build_${Target}" ) {
        Log-Information "Clean build directory (${Target})"
        Remove-Item -Path "build_${Target}" -Recurse -Force
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
    $Options = @(
        $CmakeOptions
        "-DBUILD_SHARED_LIBS:BOOL=$($OnOff[$Shared])"
        '-DENABLE_CLI:BOOL=OFF'
        '-DENABLE_TESTING:BOOL=OFF'
    )

    Invoke-External cmake -S source -B "build_${Target}" @Options
}

function Build {
    Log-Information "Build (${Target})"
    Set-Location $Path

    $Options = @(
        '--build', "build_${Target}"
        '--config', $Configuration
    )

    if ( $VerbosePreference -eq 'Continue' ) {
        $Options += '--verbose'
    }

    Invoke-External cmake @Options
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
        # CMake with MSVC produces x265.lib in the lib directory already,
        # but ensure it's named correctly for FFmpeg's pkg-config detection
        if ( Test-Path "$($script:ConfigData.OutputPath)/lib/x265.lib" ) {
            Log-Debug "Import library already correctly named: x265.lib"
        } elseif ( Test-Path "$($script:ConfigData.OutputPath)/lib/libx265.lib" ) {
            Rename-Item "$($script:ConfigData.OutputPath)/lib/libx265.lib" -NewName "x265.lib"
        }
    }
}
