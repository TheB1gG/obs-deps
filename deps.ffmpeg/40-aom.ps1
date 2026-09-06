param(
    [string] $Name = 'aom',
    [string] $Version = '3.15.0',
    [string] $Uri = 'https://aomedia.googlesource.com/aom.git',
    [string] $Hash = 'de4c1d1edc49723a78954d30a83690aa1937422f',
    [array] $Targets = @('x64', 'arm64')
)

function Setup {
    Setup-Dependency -Uri $Uri -Hash $Hash -DestinationPath $Path

    if ( ! ( $SkipAll -or $SkipDeps ) ) {
        Invoke-External pacman.exe -S --noconfirm --needed --noprogressbar nasm
    }
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

    $OnOff = @('OFF', 'ON')
    $TargetCPUs = @{
        x64 = 'x86_64'
        arm64 = 'arm64'
    }

    $Options = @(
        $CmakeOptions
        "-DBUILD_SHARED_LIBS:BOOL=$($OnOff[$script:Shared.isPresent])"
        '-DENABLE_DOCS:BOOL=OFF'
        '-DENABLE_EXAMPLES:BOOL=OFF'
        '-DENABLE_TESTDATA:BOOL=OFF'
        '-DENABLE_TESTS:BOOL=OFF'
        '-DENABLE_APPS:BOOL=OFF'
        '-DENABLE_NASM:BOOL=ON'
        "-DAOM_TARGET_CPU=$($TargetCPUs[$Target])"
    )

    Invoke-External cmake -S . -B "build_${Target}" -T clangcl @Options
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

    $Options += @($CmakePostfix)

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
