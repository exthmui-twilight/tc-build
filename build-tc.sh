#!/usr/bin/env bash

set -eo pipefail

# Function to show an informational message
function msg() {
    echo -e "\e[1;32m$@\e[0m"
}

rm -rf installTmp

# Build LLVM
msg "Building LLVM..."
./build-llvm.py \
	--build-stage1-only \
	--install-stage1-only \
	--target "ARM;AArch64;X86" \
	--projects "clang;lld;polly" \
	--install-folder "installTmp" \
	--clang-vendor "Twilight-$(date +%Y%m)"

# Build binutils
msg "Building binutils..."
if [ $(which clang) ] && [ $(which clang++) ]; then
	export CC=$(which ccache)" clang"
	export CXX=$(which ccache)" clang++"
	[ $(which llvm-strip) ] && stripBin=llvm-strip
else
	export CC=$(which ccache)" gcc"
	export CXX=$(which ccache)" g++"
	[ $(which strip) ] && stripBin=strip
fi
./build-binutils.py \
	--targets arm aarch64 x86_64 \
	--install-folder "installTmp"

# Remove unused products
msg "Removing unused products..."
rm -f installTmp/lib/*.a installTmp/lib/*.la installTmp/lib/clang/*/lib/linux/*.a*

msg "Setting library load paths for portability and"
msg "Stripping remaining products..."
IFS=$'\n'
for f in $(find installTmp -type f -exec file {} \;); do
	if [ -n "$(echo $f | grep 'ELF .* interpreter')" ]; then
		i=$(echo $f | awk '{print $1}'); i=${i: : -1}
		# Set executable rpaths so setting LD_LIBRARY_PATH isn't necessary
		if [ -d $(dirname $i)/../lib/ldscripts ]; then
			patchelf --set-rpath '$ORIGIN/../../lib:$ORIGIN/../lib' "$i"
		else
			if [ "$(patchelf --print-rpath $i)" != "\$ORIGIN/../../lib:\$ORIGIN/../lib" ]; then
				patchelf --set-rpath '$ORIGIN/../lib' "$i"
			fi
		fi
		# Strip remaining products
		if [ -n "$(echo $f | grep 'not stripped')" ]; then
			strip --strip-unneeded "$i"
		fi
	elif [ -n "$(echo $f | grep 'ELF .* relocatable')" ]; then
		if [ -n "$(echo $f | grep 'not stripped')" ]; then
			i=$(echo $f | awk '{print $1}');
			strip --strip-unneeded "${i: : -1}"
		fi
	else
		if [ -n "$(echo $f | grep 'not stripped')" ]; then
			i=$(echo $f | awk '{print $1}');
			strip --strip-all "${i: : -1}"
		fi
	fi
done

rm -rf ./install
mv installTmp/ install/

msg "binutils HEAD: $(git -C binutils-*/ rev-parse HEAD)"
msg "llvm-project HEAD: $(git -C llvm-project/ rev-parse HEAD)"
