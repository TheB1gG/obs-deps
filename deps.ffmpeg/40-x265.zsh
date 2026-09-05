autoload -Uz log_debug log_error log_info log_status log_output

## Dependency Information
local name='x265'
local -A versions=(
  macos 4.3
  linux 4.3
  windows 4.3
)
local url='https://github.com/multicorewareinc/x265.git'
local -A hashes=(
  macos e9b88125dc21393b3fd8d68e98083bdfb89778a8
  linux e9b88125dc21393b3fd8d68e98083bdfb89778a8
  windows e9b88125dc21393b3fd8d68e98083bdfb89778a8
)

## Dependency Overrides
local script_order=${${(s:-:)0:t:r}[1]}

if (( script_order < 99 )) {
  if [[ ${target} =~ 'windows'* ]] {
    local -i shared_libs=0
  } else {
    local -i shared_libs=1
  }
} else {
  local -a targets=('windows-x*')
  local -i shared_libs=1
  suffix="-shared"
}

## Build Steps
setup() {
  log_info "Setup (%F{3}${target}%f)"
  setup_dep ${url} ${hash}
}

clean() {
  cd ${dir}

  if [[ ${clean_build} -gt 0 && -d build_${arch}${suffix:-} ]] {
    log_info "Clean build directory (%F{3}${target}%f)"

    rm -rf build_${arch}${suffix:-}
  }
}

config() {
  autoload -Uz mkcd progress

  case ${target} {
    macos-universal)
      autoload -Uz universal_config && universal_config
      return
      ;;
  }

  local _onoff=(OFF ON)

  args=(
    ${cmake_flags}
    -DBUILD_SHARED_LIBS="${_onoff[(( shared_libs + 1 ))]}"
    -DENABLE_CLI=OFF
    -DENABLE_TESTING=OFF
  )

  log_info "Config (%F{3}${target}%f)"
  cd ${dir}
  log_debug "CMake configuration options: ${args}'"
  progress cmake -S source -B build_${arch}${suffix:-} -G Ninja ${args}
}

build() {
  autoload -Uz mkcd progress

  case ${target} {
    macos-universal)
      autoload -Uz universal_build && universal_build
      return
      ;;
  }

  log_info "Build (%F{3}${target}%f)"

  cd ${dir}

  args=(
    --build build_${arch}${suffix:-}
    --config ${config}
  )

  if (( _loglevel > 1 )) args+=(--verbose)

  cmake ${args}
}

install() {
  autoload -Uz progress

  log_info "Install (%F{3}${target}%f)"

  args=(
    --install build_${arch}${suffix:-}
    --config ${config}
  )

  if (( _loglevel > 1 )) args+=(--verbose)

  cd ${dir}
  progress cmake ${args}
}

fixup() {
  cd "${dir}"

  log_info "Fixup (%F{3}${target}%f)"

  local strip_tool
  local -a strip_files

  case ${target} {
    macos*)
      if (( shared_libs )) {
        local -a dylib_files=(${target_config[output_dir]}/lib/libx265*.dylib(.))

        autoload -Uz fix_rpaths && fix_rpaths ${dylib_files}

        if [[ ${config} == Release ]] dsymutil ${dylib_files}

        strip_tool=strip
        strip_files=(${dylib_files})
      } else {
        rm -rf -- ${target_config[output_dir]}/lib/libx265*.(dylib|dSYM)(N)
      }
      ;;
    linux-*)
      if (( shared_libs )) {
        strip_tool=strip
        strip_files=(${target_config[output_dir]}/lib/libx265.so.*(.))
      } else {
        rm -rf -- ${target_config[output_dir]}/lib/libx265.so.*(N)
      }
      ;;
    windows-x*)
      if (( shared_libs )) {
        autoload -Uz create_importlibs
        create_importlibs ${target_config[output_dir]}/bin/libx265*.dll(.)

        rm -f ${target_config[output_dir]}/bin/x265.exe(N)
        strip_tool=${target_config[cross_prefix]}-w64-mingw32-strip
        strip_files=(${target_config[output_dir]}/bin/libx265*.dll(.))
      } else {
        rm -rf -- ${target_config[output_dir]}/bin/libx265*.dll(N)
      }
      ;;
  }

  if (( #strip_files )) && [[ ${config} == (Release|MinSizeRel) ]] ${strip_tool} -x ${strip_files}
}
