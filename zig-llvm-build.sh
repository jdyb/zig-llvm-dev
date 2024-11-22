#!/bin/bash

POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
  case $1 in
    --zig-checkout)
      ZIG_CHECKOUT="$2"
      shift # past argument
      shift # past value
      ;;
    --llvm-checkout)
      LLVM_CHECKOUT="$2"
      shift # past argument
      shift # past value
      ;;
    --build-type)
      BUILD_TYPE="$2"
      shift # past argument
      shift # past value
      ;;
    -*|--*)
      echo "Unknown option $1"
      exit 1
      ;;
    *)
      echo "Unknown option $1"
      exit 1
  esac
done

if [ -z "${ZIG_CHECKOUT}" ]; then
  echo "No --zig-checkout"
  exit 1
fi

if [ -z "${LLVM_CHECKOUT}" ]; then
  echo "No --llvm-checkout"
  exit 1
fi

if [ -z "${BUILD_TYPE}" ]; then
  echo "No --build-type"
  exit 1
fi

USERTMPDIR=/var/tmp/$USER
CACHEDIR=$USERTMPDIR/cache/

WORKDIR=$USERTMPDIR/zig-dev-$ZIG_CHECKOUT-$LLVM_CHECKOUT/
LLVM_INSTALL_DIR=$WORKDIR/llvm-install/
LLVM_BUILD_DIR=$WORKDIR/llvm-build
LLVM_SRC_DIR=$WORKDIR/llvm-src
LLVM_GIT=$CACHEDIR/llvm-project.git

ZIG_GIT=$CACHEDIR/zig.git
ZIG_SRC_DIR=$WORKDIR/zig-src
ZIG_BUILD_DIR=$WORKDIR/zig-build
ZIG_INSTALL_DIR=$WORKDIR/zig-install/

JOBS=42

set -e

DISTCC_VERBOSE=0
DISTCC_HOSTS="@localhost"
CCACHE_PREFIX=distcc

which git
which cmake
which make
which date
which ccache
which distcc

git --version
cmake --version
make --version
ccache --version
distcc --version

function logvar () {
  name=$1
  echo \# $(date -Iseconds) $name=${!name}
}

function logmsg () {
  echo \# $(date -Iseconds) "$@"
}

logmsg Start

logvar CACHEDIR
logvar WORKDIR

logvar JOBS
logvar DISTCC_VERBOSE
logvar DISTCC_HOSTS

logvar ZIG_GIT
logvar ZIG_SRC_DIR
logvar ZIG_BUILD_DIR
logvar ZIG_INSTALL_DIR

logvar LLVM_GIT
logvar LLVM_SRC_DIR
logvar LLVM_BUILD_DIR
logvar LLVM_INSTALL_DIR

mkdir -p $CACHEDIR
mkdir -p $LLVM_INSTALL_DIR
mkdir -p $LLVM_BUILD_DIR
mkdir -p $ZIG_INSTALL_DIR
mkdir -p $ZIG_BUILD_DIR

if [ ! -d $LLVM_GIT ]; then
  logmsg Initial clone of llvm
  cd $CACHEDIR
  git clone --bare https://github.com/llvm/llvm-project
else
  logmsg Fetch llvm changes
  cd $LLVM_GIT
  git fetch
fi

if [ ! -d $ZIG_GIT ]; then
  logmsg Initial clone of zig
  cd $CACHEDIR
  git clone --bare https://github.com/ziglang/zig.git
else
  logmsg Fetch zig changes
  cd $ZIG_GIT
  git fetch
fi

if [ ! -d $LLVM_SRC_DIR ]; then
  logmsg "Checkout llvm-src ($LLVM_CHECKOUT)"
  cd $WORKDIR
  git clone --shared --branch $LLVM_CHECKOUT $LLVM_GIT llvm-src/
  # TODO If the checkout is a branch, pull.
fi

if [ ! -d $ZIG_SRC_DIR ]; then
  logmsg "Checkout zig-src ($ZIG_CHECKOUT)"
  cd $WORKDIR
  git clone --shared --branch $ZIG_CHECKOUT $ZIG_GIT zig-src/
  # TODO If the checkout is a branch, pull.
fi

logmsg CMAKE on llvm
cd $LLVM_BUILD_DIR
cmake $LLVM_SRC_DIR/llvm \
  -DCMAKE_INSTALL_PREFIX=$LLVM_INSTALL_DIR \
  -DCMAKE_BUILD_TYPE=$BUILD_TYPE \
  -DLLVM_CCACHE_BUILD=On \
  -DLLVM_ENABLE_PROJECTS="lld;clang" \
  -DLLVM_ENABLE_LIBXML2=OFF \
  -DLLVM_ENABLE_TERMINFO=OFF \
  -DLLVM_ENABLE_LIBEDIT=OFF \
  -DLLVM_ENABLE_ASSERTIONS=ON \
  -DLLVM_PARALLEL_LINK_JOBS=1 \
  -G "Unix Makefiles"

logmsg LLVM make
make -j $JOBS

logmsg LLVM install
make install

logmsg LLVM test
make test -j $JOBS

logmsg ZIG cmake
cd $ZIG_BUILD_DIR
cmake $ZIG_SRC_DIR \
  -DCMAKE_PREFIX_PATH=$LLVM_INSTALL_DIR \
  -DCMAKE_INSTALL_PREFIX=$ZIG_INSTALL_DIR \
  -DCMAKE_BUILD_TYPE=$BUILD_TYPE

logmsg ZIG make
make -j $JOBS

logmsg ZIG install
make install -j $JOBS

logmsg ZIG version
$ZIG_INSTALL_DIR/bin/zig version

logmsg Done
