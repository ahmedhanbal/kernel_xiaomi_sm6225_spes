#!/bin/bash
set -e

# --------------------------
# Argument Required
# --------------------------
if [ -z "$1" ]; then
  echo "Error: No build variant specified!"
  echo
  echo "Usage:"
  echo "  ./build.sh base"
  echo "  ./build.sh su"
  echo "  ./build.sh all"
  exit 1
fi

TARGET="$1"

# --------------------------
# Setup
# --------------------------
KERNEL_ROOT=$(pwd)
OUTDIR="$KERNEL_ROOT/out"
DATE_TIME=$(TZ="Asia/Karachi" date +"%d%m%y-%H%M%S")

MAKE_ARGS="
O=out
CC=clang
LD=ld.lld
LLVM=1
LLVM_IAS=1
ARCH=arm64
SUBARCH=arm64
CROSS_COMPILE=aarch64-linux-gnu-
CROSS_COMPILE_ARM32=arm-linux-gnueabi-
"

# --------------------------
# Variants to build
# --------------------------
if [ "$TARGET" == "all" ]; then
  VARIANTS=("su" "base")
elif [ "$TARGET" == "base" ] || [ "$TARGET" == "su" ]; then
  VARIANTS=("$TARGET")
else
  echo "Error: Invalid variant '$TARGET'"
  echo
  echo "Valid options: base | su | all"
  exit 1
fi

# --------------------------
# Clone AnyKernel once
# --------------------------
if [ ! -d "anykernel-template" ]; then
  echo "Cloning AnyKernel template..."
  git clone --depth=1 https://github.com/ahmedhanbal/anykernel anykernel-template
  rm -rf anykernel-template/.git
fi

# --------------------------
# Build Loop
# --------------------------
for VARIANT in "${VARIANTS[@]}"; do
  echo "========================================="
  echo " Building Variant: $VARIANT"
  echo "========================================="

  BRANCH="16.0-perf-ksu"

  echo "Switching to branch: $BRANCH"
  git checkout "$BRANCH"
	# ---------------------------------
	# Switch KernelSU-Next branch
	# ---------------------------------
	if [ "$VARIANT" == "su" ]; then
 	     echo "Switching KernelSU-Next to legacy"
             curl -LSs "https://raw.githubusercontent.com/backslashxx/KernelSU/master/kernel/setup.sh" | bash -
	fi
  # --------------------------
  # Defconfig
  # --------------------------
  make $MAKE_ARGS vendor/spes-stock_defconfig vendor/xiaomi/spes.config

  # --------------------------
  # Variant LOCALVERSION
  # --------------------------
  LOCALV="-$VARIANT"

  # --------------------------
  # KernelSU config only for su
  # --------------------------
  if [ "$VARIANT" = "base" ]; then
	scripts/config --file out/.config -d CONFIG_KSU
        scripts/config --file out/.config -d CONFIG_KSU_TAMPER_SYSCALL_TABLE
        scripts/config --file out/.config -d CONFIG_KSU_FEATURE_SULOG
        scripts/config --file out/.config -d CONFIG_KSU_FEATURE_ADBROOT
        scripts/config --file out/.config -d CONFIG_KSU_DEBUG
        scripts/config --file out/.config -d CONFIG_KSU_THRONE_TRACKER_ALWAYS_THREADED
        scripts/config --file out/.config -d CONFIG_KSU_LSM_SECURITY_HOOKS
  fi
  # --------------------------
  # Compile Kernel
  # --------------------------
  echo "Compiling kernel..."
  make -j$(nproc --all) $MAKE_ARGS LOCALVERSION=$LOCALV Image.gz-dtb dtbo.img

  # --------------------------
  # Prepare AnyKernel Folder
  # --------------------------
  ANYKERNEL_DIR="anykernel-$VARIANT"
  rm -rf "$ANYKERNEL_DIR"
  cp -r anykernel-template "$ANYKERNEL_DIR"

  # Copy outputs
  cp "$OUTDIR/arch/arm64/boot/Image.gz-dtb" "$ANYKERNEL_DIR/"
  cp "$OUTDIR/arch/arm64/boot/dtbo.img" "$ANYKERNEL_DIR/"

  # --------------------------
  # Patch kernel.string in anykernel.sh
  # --------------------------
  echo "Patching anykernel.sh kernel string..."
  sed -i "s/^kernel.string=.*/kernel.string=hanbal-gforce-$VARIANT/" \
    "$ANYKERNEL_DIR/anykernel.sh"

  # --------------------------
  # Zip Packaging
  # --------------------------
  ZIPNAME="hanbal-gforce-${VARIANT}-${DATE_TIME}.zip"

  echo "Creating flashable zip: $ZIPNAME"

  (
    cd "$ANYKERNEL_DIR"
    zip -r9 "../$ZIPNAME" . -x "*.git*"
  )

  echo "Done: $ZIPNAME created!"
  echo
done

echo "========================================="
echo " Build Finished Successfully"
echo "========================================="
ls -lh hanbal-gforce-*-${DATE_TIME}.zip
