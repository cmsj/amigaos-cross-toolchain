#!/bin/bash -Eeux

readonly TOP_DIR="$(pwd)"
readonly ARCHIVES="${TOP_DIR}/archives"
readonly PATCHES="${TOP_DIR}/patches"
readonly SOURCES="${TOP_DIR}/sources"
readonly BUILD_DIR="${TOP_DIR}/build"
readonly HOST_DIR="${TOP_DIR}/host"
readonly STAMP="${TOP_DIR}/stamps"

source "${TOP_DIR}/bootstrap.conf"

function prepare_target {
  mkdir -p "${STAMP}" "${BUILD_DIR}" "${PREFIX}"

  [ -f "${STAMP}/prepare-target" ] && return 0

  pushd "${PREFIX}"
  mkdir -p "m68k-amigaos" "lib" "os-include" "os-lib"
  ln -sf "../os-include" "m68k-amigaos/include"
  ln -sf "../lib" "m68k-amigaos/lib"
  popd

  touch "${STAMP}/prepare-target"
}

function copy_non_diff {
  find "${PATCHES}/$1" -type f \! -name '*.diff' | while read IN ; do
    OUT=$(echo "$IN" | sed -e "s,$PATCHES/,$SOURCES/,g")
    cp "$IN" "$OUT"
  done
}

function apply_patches {
  for file in $(find "${PATCHES}/$1" -type f -iname '*.diff' | sort); do
    patch -i $file -t -p1
  done
}

function mkdir_empty {
  rm -rf "$1"
  mkdir -p "$1"
}

function unpack_clean {
  local cmd

  rm -rf "$1"

  while (( "$#" > 1 )); do
    shift

    if grep "\.tar\.gz$" <<<"$1"; then
      cmd="tar -xzf"
    elif grep "\.tar.bz2$" <<<"$1"; then
      cmd="tar -xjf"
    elif grep "\.lha$" <<<"$1"; then
      cmd="lha -xgq"
    else
      cmd="false"
    fi

    ${cmd} "${ARCHIVES}/$1"
  done
}

function compare_version {
  python - "$1" "$2" "$3" <<EOF
from distutils.version import StrictVersion
import sys

cmp = lambda x, y: StrictVersion(x).__cmp__(y)

op = {"lt": [-1],    "gt": [1],
      "le": [-1, 0], "ge": [1, 0],
      "eq": [0],     "ne": [-1, 1]}

res = cmp(sys.argv[1], sys.argv[3]) in op[sys.argv[2]]

sys.exit(int(not res))
EOF
}

function unpack_sources {
  [ -f "${STAMP}/unpack-sources" ] && return 0

  rm -rf "${SOURCES}"
  mkdir -p "${SOURCES}"
  pushd "${SOURCES}"

  unpack_clean "${BINUTILS}" "${BINUTILS_SRC}"
  pushd "${BINUTILS}"
  apply_patches "${BINUTILS}"
  copy_non_diff "${BINUTILS}"
  popd

  unpack_clean "${GCC}" "${GCC_CORE_SRC}" "${GCC_CPP_SRC}"
  pushd "${GCC}"
  apply_patches "${GCC}"
  copy_non_diff "${GCC}"
  popd

  if compare_version "${GCC_VER}" "ge" "4.0.0"; then
    unpack_clean "${GMP}" "${GMP_SRC}"
    unpack_clean "${MPC}" "${MPC_SRC}"
    unpack_clean "${MPFR}" "${MPFR_SRC}"
    unpack_clean "${ISL}" "${ISL_SRC}"
    unpack_clean "${CLOOG}" "${CLOOG_SRC}"
  fi

  unpack_clean "${SFDC}" "${SFDC_SRC}"
  tar -xzf "${SFDC}.tar.gz"
  for file in $(ls -1d sfdc*); do
    [ -f "${file}" ] && rm "${file}"
  done

  unpack_clean "${NDK}" "${NDK_SRC}"
  rm -rf ndk_* *.info
  pushd "${NDK}"
  mkdir Include/include_h/inline
  apply_patches "${NDK}"
  copy_non_diff "${NDK}"
  popd

  unpack_clean "${IXEMUL}" "${IXEMUL_SRC}"
  mv "ixemul" "${IXEMUL}"
  pushd "${IXEMUL}"
  chmod a+x "configure" "mkinstalldirs"
  apply_patches "${IXEMUL}"
  popd

  unpack_clean "${LIBNIX}" "${LIBNIX_SRC}"
  mv "libnix" "${LIBNIX}"
  chmod a+x "${LIBNIX}/mkinstalldirs"

  mkdir_empty "${LIBAMIGA}"
  pushd "${LIBAMIGA}"
  tar -xzf "${ARCHIVES}/${LIBAMIGA_SRC}"
  popd

  unpack_clean "${BISON}" "${BISON_SRC}"
  unpack_clean "${GAWK}" "${GAWK_SRC}"

  popd

  touch "${STAMP}/unpack-sources"
}

function build_tools {
  [ -f "${STAMP}/build-tools" ] && return 0

  mkdir_empty "${HOST_DIR}"

  pushd "${BUILD_DIR}"

  mkdir_empty "${GAWK}"
  pushd "${GAWK}"
  "${SOURCES}/${GAWK}/configure" \
    --prefix="${HOST_DIR}"
  make && make install
  popd

  if compare_version "${GCC_VER}" "eq" "2.95.3"; then
    mkdir_empty "${BISON}"
    pushd "${BISON}"
    "${SOURCES}/${BISON}/configure" \
      --prefix="${HOST_DIR}"
    make && make install
    popd
  fi

  if compare_version "${GCC_VER}" "ge" "4.0.0"; then
    mkdir_empty "${GMP}"
    pushd "${GMP}"
    "${SOURCES}/${GMP}/configure" \
      --prefix="${HOST_DIR}"
    make && make install
    popd

    mkdir_empty "${MPFR}"
    pushd "${MPFR}"
    "${SOURCES}/${MPFR}/configure" \
      --prefix="${HOST_DIR}" \
      --with-gmp="${HOST_DIR}"
    make && make install
    popd

    mkdir_empty "${MPC}"
    pushd "${MPC}"
    "${SOURCES}/${MPC}/configure" \
      --prefix="${HOST_DIR}" \
      --with-gmp="${HOST_DIR}" \
      --with-mpfr="${HOST_DIR}"
    make && make install
    popd

    mkdir_empty "${ISL}"
    pushd "${ISL}"
    "${SOURCES}/${ISL}/configure" \
      --prefix="${HOST_DIR}"
    make && make install
    popd

    mkdir_empty "${CLOOG}"
    pushd "${CLOOG}"
    "${SOURCES}/${CLOOG}/configure" \
      --prefix="${HOST_DIR}" \
      --with-isl=system \
      --with-gmp-prefix="${HOST_DIR}" \
      --with-isl-prefix="${HOST_DIR}"
    make && make install
    popd
  fi

  popd

	touch "${STAMP}/build-tools"
}

function build_binutils {
  [ -f "${STAMP}/build-binutils" ] && return 0

  pushd "${BUILD_DIR}"
	rm -rf "${BINUTILS}"
	mkdir -p "${BINUTILS}"
  cd "${BINUTILS}"
  "${SOURCES}/${BINUTILS}/configure" \
    --prefix="${PREFIX}" \
    --host="i686-linux-gnu" \
    --target="m68k-amigaos"
  make all
  make install install-info
  popd

	touch "${STAMP}/build-binutils"
}

function build_gcc {
  [ -f "${STAMP}/build-gcc" ] && return 0

  pushd "${BUILD_DIR}"
	rm -rf "${GCC}"
	mkdir -p "${GCC}"
  cd "${GCC}"
  "${SOURCES}/${GCC}/configure" \
    --prefix="${PREFIX}" \
    --target="m68k-amigaos" \
    --host="i686-linux-gnu" \
    --enable-languages=c \
    --with-headers="${SOURCES}/${IXEMUL}/include"
  make all ${FLAGS_FOR_TARGET[*]}
  make install ${FLAGS_FOR_TARGET[*]}
  popd

	touch "${STAMP}/build-gcc"
}

function build_gpp {
  [ -f "${STAMP}/build-gpp" ] && return 0

  pushd "${BUILD_DIR}"
	rm -rf "${GCC}"
	mkdir -p "${GCC}"
  cd "${GCC}"
  "${SOURCES}/${GCC}/configure" \
    --prefix="${PREFIX}" \
    --host="i686-linux-gnu" \
    --target="m68k-amigaos" \
    --enable-languages=c++ \
    --with-headers="${SOURCES}/${IXEMUL}/include"
  make all ${FLAGS_FOR_TARGET[*]}
  make install ${FLAGS_FOR_TARGET[*]}
  popd

	touch "${STAMP}/build-gpp"
}

function process_headers {
  [ -f "${STAMP}/process-headers" ] && return 0

  pushd "${BUILD_DIR}"
	rm -rf "${SFDC}"
	cp -a "${SOURCES}/${SFDC}" "${SFDC}"
  cd "${SFDC}"
  ./configure \
    --prefix="${PREFIX}"
  make
	make install
  popd

  pushd "${PREFIX}/include"
  cp -av "${SOURCES}/${NDK}/Include/include_h/"* .
  for file in ${SOURCES}/${NDK}/Include/sfd/*.sfd; do
    base=$(basename ${file%_lib.sfd})

    sfdc --target=m68k-amigaos --mode=proto \
      --output="proto/${base}.h" $file
    sfdc --target=m68k-amigaos --mode=macros \
      --output="inline/${base}.h" $file
  done
  popd

	touch "${STAMP}/process-headers"
}

function install_libamiga {
  [ -f "${STAMP}/install-libamiga" ] && return 0

  pushd "${PREFIX}"
  cp -av "${SOURCES}/${LIBAMIGA}/lib" .
  popd

	touch "${STAMP}/install-libamiga"
}

function build_libnix {
  [ -f "${STAMP}/build-libnix" ] && return 0

  pushd "${BUILD_DIR}"
	rm -rf "${LIBNIX}"
	mkdir -p "${LIBNIX}"
  cd "${LIBNIX}"
  "${SOURCES}/${LIBNIX}/configure" \
    --prefix="${PREFIX}" \
    --host="i686-linux-gnu" \
    --target="m68k-amigaos"
  make all \
    CC=m68k-amigaos-gcc \
    CPP="m68k-amigaos-gcc -E" \
    AR=m68k-amigaos-ar \
    AS=m68k-amigaos-as \
    RANLIB=m68k-amigaos-ranlib \
    LD=m68k-amigaos-ld \
    MAKEINFO=:
  [ -f "${PREFIX}/guide" ] && rm -f "${PREFIX}/guide"
  make install MAKEINFO=:
  popd

	touch "${STAMP}/build-libnix"
}

function build_ixemul {
  [ -f "${STAMP}/build-ixemul" ] && return 0

  pushd "${BUILD_DIR}"
	rm -rf "${IXEMUL}"
	mkdir -p "${IXEMUL}"
  cd "${IXEMUL}"
  CC=m68k-amigaos-gcc \
  CFLAGS="-noixemul -I${PREFIX}/include" \
  AR=m68k-amigaos-ar \
  RANLIB=m68k-amigaos-ranlib \
	"${SOURCES}/${IXEMUL}/configure" \
    --prefix="${PREFIX}" \
    --host="i686-linux-gnu" \
    --target="m68k-amigaos"
  make MAKEINFO=: all
  make MAKEINFO=: install
  popd

	touch "${STAMP}/build-ixemul"
}

function build {
  # On 64-bit architecture GNU Assembler crashes writing out an object, due to
  # (probably) miscalculated structure sizes.  There could be some other bugs
  # lurking there in 64-bit mode, but I have little incentive chasing them.
  # Just compile everything in 32-bit mode and forget about the issues.
  if [ "$(uname -m)" == "x86_64" ]; then
    CFLAGS="-m32"
  else
    CFLAGS=""
  fi

  # Take the path over -- for hermeticity reasons.
  export PATH="/opt/local/bin:/usr/local/bin:/usr/bin:/bin"

  # Make sure we always choose known compiler (from the distro) and not one
  # in user's path that could shadow the original one.
  export CC="$(which gcc) ${CFLAGS}"

  prepare_target
  unpack_sources
  build_tools

  export PATH="${HOST_DIR}/bin:${PATH}"

  build_binutils
  build_gcc

  export PATH="${PREFIX}/bin:${PATH}"

  process_headers
  install_libamiga
  build_libnix
  build_gpp
  build_ixemul
}

function main {
  PREFIX="${TOP_DIR}/target"

  local action="build"

  while [ -n "${1:-}" ]; do
    case "$1" in
      --prefix=*)
        PREFIX=${1#*=}
        ;;
      --clean)
        action="clean"
        ;;
      *)
        echo "Unknown option: $1"
        exit 1
        ;;
    esac
    shift
  done

  readonly FLAGS_FOR_TARGET=( \
      "MAKEINFO=makeinfo" \
      "CFLAGS_FOR_TARGET=-noixemul" \
      "AR_FOR_TARGET=${PREFIX}/bin/m68k-amigaos-ar" \
      "AS_FOR_TARGET=${PREFIX}/bin/m68k-amigaos-as" \
      "LD_FOR_TARGET=${PREFIX}/bin/m68k-amigaos-ld" \
      "NM_FOR_TARGET=${PREFIX}/bin/m68k-amigaos-nm" \
      "OBJCOPY_FOR_TARGET=${PREFIX}/bin/m68k-amigaos-objcopy" \
      "OBJDUMP_FOR_TARGET=${PREFIX}/bin/m68k-amigaos-objdump" \
      "RANLIB_FOR_TARGET=${PREFIX}/bin/m68k-amigaos-ranlib")

  case "${action}" in
    "build")
      build
      ;;
    "clean")
      for dir in ${SOURCES} ${BUILD_DIR} ${HOST_DIR} ${STAMP}; do
        rm -rf "${dir}"
      done
      ;;
    *)
      echo "action '${action}' not supported!"
      exit 1
      ;;
  esac
}

main "$@"
