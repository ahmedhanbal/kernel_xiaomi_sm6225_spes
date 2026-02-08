#!/bin/bash
# script to build both base and ksunext variant locally in one go without rebuild for both variants
set -e

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
VARIANTS=("base" "suNext" "suNext-M")

# --------------------------
# Clone AnyKernel once
# --------------------------
if [ ! -d "anykernel-template" ]; then
  echo "Cloning AnyKernel template..."
  git clone --depth=1 https://github.com/ahmedhanbal/anykernel anykernel-template
  rm -rf anykernel-template/.git
fi

# --------------------------
# Defconfig
# --------------------------
make $MAKE_ARGS vendor/spes-stock_defconfig


# --------------------------
# Build Loop
# --------------------------
for VARIANT in "${VARIANTS[@]}"; do
  echo "========================================="
  echo " Building Variant: $VARIANT"
  echo "========================================="

  # --------------------------
  # Variant-specific config + LOCALVERSION
  # --------------------------
  LOCALV="-$VARIANT"

  if [ "$VARIANT" == "suNext" ]; then
    echo "Enabling KernelSU..."
    ./scripts/config --file "$OUTDIR/.config" -e CONFIG_KSU
    ./scripts/config --file "$OUTDIR/.config" -d CONFIG_KSU_MANUAL_HOOK
    ./scripts/config --file "$OUTDIR/.config" -d CONFIG_KSU_ALLOWLIST_WORKAROUND
    ./scripts/config --file "$OUTDIR/.config" -d CONFIG_KSU_DEBUG
    ./scripts/config --file "$OUTDIR/.config" -e CONFIG_KSU_KPROBES_HOOK
  elif [ "$VARIANT" == "suNext-M" ]; then
    echo "Enabling KernelSU with Manual Hooks"
    ./scripts/config --file "$OUTDIR/.config" -e CONFIG_KSU
    ./scripts/config --file "$OUTDIR/.config" -e CONFIG_KSU_MANUAL_HOOK
    ./scripts/config --file "$OUTDIR/.config" -d CONFIG_KSU_ALLOWLIST_WORKAROUND
    ./scripts/config --file "$OUTDIR/.config" -d CONFIG_KSU_DEBUG
    ./scripts/config --file "$OUTDIR/.config" -d CONFIG_KSU_KPROBES_HOOK
  else
    echo "Disabling KernelSU..."
    ./scripts/config --file "$OUTDIR/.config" -d CONFIG_KSU
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
  sed -i "s/^kernel.string=.*/kernel.string=4.19.325-hanbal-gforce-$VARIANT/" \
    "$ANYKERNEL_DIR/anykernel.sh"

  # --------------------------
  # Zip Packaging (flat structure)
  # --------------------------
  ZIPNAME="hanbal-gforce-${VARIANT}-${DATE_TIME}.zip"

  echo "Creating flashable zip: $ZIPNAME"

  (
    cd "$ANYKERNEL_DIR"
    zip -r9 "../$ZIPNAME" . -x "*.git*"
  )

  echo "✅ Done: $ZIPNAME created in kernel root!"
  echo
done

echo "========================================="
echo " All Builds Completed Successfully"
echo "========================================="
ls -lh hanbal-gforce-*.zip
