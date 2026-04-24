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
  echo "  ./build.sh suNext"
  echo "  ./build.sh susNext"
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
  VARIANTS=("susNext" "suNext" "base")
elif [ "$TARGET" == "base" ] || [ "$TARGET" == "suNext" ] || [ "$TARGET" == "susNext" ]; then
  VARIANTS=("$TARGET")
else
  echo "Error: Invalid variant '$TARGET'"
  echo
  echo "Valid options: base | suNext | all"
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

  BRANCH="16.0-perf"

  echo "Switching to branch: $BRANCH"
  git checkout "$BRANCH"
	# ---------------------------------
	# Switch KernelSU-Next branch
	# ---------------------------------
	if [ "$VARIANT" == "suNext" ]; then
 	     echo "Switching KernelSU-Next to legacy"
             curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh" | bash -s legacy
	elif [ "$VARIANT" == "susNext" ]; then
             echo "Switching KernelSU-Next to legacy_susfs"
             curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh" | bash -s legacy-susfs
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
  # KernelSU config only for suNext
  # --------------------------
  case "$VARIANT" in
    suNext|susNext)
       scripts/config --file out/.config -e CONFIG_KSU
       scripts/config --file out/.config -d CONFIG_KSU_MANUAL_HOOK
       scripts/config --file out/.config -d CONFIG_KSU_ALLOWLIST_WORKAROUND
       scripts/config --file out/.config -d CONFIG_KSU_DEBUG
       scripts/config --file out/.config -e CONFIG_KSU_KPROBES_HOOK

       if [ "$VARIANT" = "suNext" ]; then
         scripts/config --file out/.config -d CONFIG_KSU_SUSFS
       else
         scripts/config --file out/.config -d CONFIG_KSU_SUSFS_TRY_UMOUNT
       fi
       ;;
    *)
       scripts/config --file out/.config -d CONFIG_KSU
       ;;
    esac
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
