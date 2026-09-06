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
        # CMake with MSVC produces the import library in the lib directory.
        # Ensure both x265.lib and libx265.lib are present: x265.lib is what
        # FFmpeg's pkg-config detection resolves to during the build, while
        # libx265.lib makes x265 discoverable through CMake's normal dependency
        # chain in the prebuilt package (matching the libx264.lib convention).
        $LibDir = "$($script:ConfigData.OutputPath)/lib"

        if ( Test-Path "$LibDir/x265.lib" ) {
            if ( -not ( Test-Path "$LibDir/libx265.lib" ) ) {
                Copy-Item "$LibDir/x265.lib" "$LibDir/libx265.lib"
                Log-Debug "Created libx265.lib from x265.lib for CMake discovery"
            }
        } elseif ( Test-Path "$LibDir/libx265.lib" ) {
            Copy-Item "$LibDir/libx265.lib" "$LibDir/x265.lib"
            Log-Debug "Created x265.lib from libx265.lib for FFmpeg pkg-config detection"
        } else {
            Log-Warning "No x265 import library found in ${LibDir}"
        }
    }
}
