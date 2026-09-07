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
local -a patches=(
  "macos ${0:a:h}/patches/x265-whole-archive.patch 0eb988dd4c8683e9c5d9f22149a002c403fe142d31acb0572670645bfd8ecc9b"
  "linux ${0:a:h}/patches/x265-whole-archive.patch 0eb988dd4c8683e9c5d9f22149a002c403fe142d31acb0572670645bfd8ecc9b"
  "windows ${0:a:h}/patches/x265-whole-archive.patch 0eb988dd4c8683e9c5d9f22149a002c403fe142d31acb0572670645bfd8ecc9b"
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

patch() {
  autoload -Uz apply_patch

  log_info "Patch (%F{3}${target}%f)"
  cd ${dir}

  local patch
  for patch (${patches}) {
    read _target _url _hash <<< "${patch}"
    if [[ ${_target} == "${target%%-*}" ]] apply_patch ${_url} ${_hash}
  }
}

clean() {
  cd ${dir}

  if (( clean_build )) {
    if [[ -d build_${arch}${suffix:-} ]] {
      log_info "Clean build directory (%F{3}build_${arch}${suffix:-}%f)"
      rm -rf build_${arch}${suffix:-}
    }
    if [[ -d build_10bit_${arch}${suffix:-} ]] {
      log_info "Clean build directory (%F{3}build_10bit_${arch}${suffix:-}%f)"
      rm -rf build_10bit_${arch}${suffix:-}
    }
    if [[ -d build_12bit_${arch}${suffix:-} ]] {
      log_info "Clean build directory (%F{3}build_12bit_${arch}${suffix:-}%f)"
      rm -rf build_12bit_${arch}${suffix:-}
    }
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

  local -a common_args=(
    ${cmake_flags}
    -DENABLE_CLI=OFF
    -DENABLE_TESTING=OFF
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON
  )

  cd ${dir}

  # 10-bit static library (namespaced symbols, no C API export)
  log_info "Config x265 10-bit static (%F{3}${target}%f)"
  local -a args_10bit=(
    ${common_args}
    -DBUILD_SHARED_LIBS=OFF
    -DENABLE_SHARED=OFF
    -DHIGH_BIT_DEPTH=ON
    -DEXPORT_C_API=OFF
  )
  log_debug "CMake configuration options (10bit): ${args_10bit}"
  progress cmake -S source -B build_10bit_${arch}${suffix:-} -G Ninja ${args_10bit}

  # 12-bit static library (namespaced symbols, no C API export)
  log_info "Config x265 12-bit static (%F{3}${target}%f)"
  local -a args_12bit=(
    ${common_args}
    -DBUILD_SHARED_LIBS=OFF
    -DENABLE_SHARED=OFF
    -DHIGH_BIT_DEPTH=ON
    -DMAIN12=ON
    -DEXPORT_C_API=OFF
  )
  log_debug "CMake configuration options (12bit): ${args_12bit}"
  progress cmake -S source -B build_12bit_${arch}${suffix:-} -G Ninja ${args_12bit}

  # Main shared library (8-bit C API + linked 10/12-bit for x265_api_get dispatch)
  log_info "Config x265 main shared (%F{3}${target}%f)"
  local -a args_main=(
    ${common_args}
    -DBUILD_SHARED_LIBS="${_onoff[(( shared_libs + 1 ))]}"
    -DEXTRA_LIB=1
    "-DEXTRA_LIB_DIR10=${PWD}/build_10bit_${arch}${suffix:-}"
    "-DEXTRA_LIB_DIR12=${PWD}/build_12bit_${arch}${suffix:-}"
    -DLINKED_10BIT=ON
    -DLINKED_12BIT=ON
  )
  log_debug "CMake configuration options (main): ${args_main}"
  progress cmake -S source -B build_${arch}${suffix:-} -G Ninja ${args_main}
}

build() {
  autoload -Uz mkcd progress

  case ${target} {
    macos-universal)
      autoload -Uz universal_build && universal_build
      return
      ;;
  }

  cd ${dir}

  local -a common_build_args=(--config ${config})
  if (( _loglevel > 1 )) common_build_args+=(--verbose)

  # Build 10-bit static first
  log_info "Build x265 10-bit static (%F{3}${target}%f)"
  progress cmake --build build_10bit_${arch}${suffix:-} ${common_build_args}

  # Build 12-bit static second
  log_info "Build x265 12-bit static (%F{3}${target}%f)"
  progress cmake --build build_12bit_${arch}${suffix:-} ${common_build_args}

  # Build main shared last (links against the other two)
  log_info "Build x265 main shared (%F{3}${target}%f)"
  progress cmake --build build_${arch}${suffix:-} ${common_build_args}
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
