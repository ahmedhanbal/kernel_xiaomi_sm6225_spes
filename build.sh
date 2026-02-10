#!/bin/bash
# Build script: base (16.0-perf) + suNext (16.0-perf-ksun)
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
  echo "  ./build.sh all"
  exit 1
fi

# --------------------------
# Git Clean Check
# --------------------------
if [ -n "$(git status --porcelain)" ]; then
  echo "Error: You have uncommitted changes in your kernel tree!"
  echo
  echo "Please commit or stash them before running this script."
  echo
  echo "Run one of these:"
  echo "  git add . && git commit -m \"save\""
  echo "  git stash"
  echo
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
  VARIANTS=("base" "suNext")
elif [ "$TARGET" == "base" ] || [ "$TARGET" == "suNext" ]; then
  VARIANTS=("$TARGET")
else
  echo "Error: Invalid variant '$TARGET'"
  echo
  echo "Valid options: base | suNext | all"
  exit 1
fi

# --------------------------
# Branch mapping
# --------------------------
get_branch() {
  case "$1" in
    base)   echo "16.0-perf" ;;
    suNext) echo "16.0-perf-ksun" ;;
  esac
}

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

  BRANCH=$(get_branch "$VARIANT")

  echo "Switching to branch: $BRANCH"
  git checkout "$BRANCH"

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
  if [ "$VARIANT" == "suNext" ]; then
    echo "Enabling KernelSU..."

    ./scripts/config --file "$OUTDIR/.config" -e CONFIG_KSU
    ./scripts/config --file "$OUTDIR/.config" -d CONFIG_KSU_MANUAL_HOOK
    ./scripts/config --file "$OUTDIR/.config" -d CONFIG_KSU_ALLOWLIST_WORKAROUND
    ./scripts/config --file "$OUTDIR/.config" -d CONFIG_KSU_DEBUG
    ./scripts/config --file "$OUTDIR/.config" -e CONFIG_KSU_KPROBES_HOOK

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
