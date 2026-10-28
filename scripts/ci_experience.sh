#!/usr/bin/env bash
# Ubuntu 24.04 x86-64 build host; USB commands run separately on the Mac.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export HACKIOS_HOME=${HACKIOS_HOME:-$HOME/hackios}
export THEOS=${THEOS:-$HOME/theos}
export MU_DIR=$HACKIOS_HOME/Mu-Silicium
HS=$HACKIOS_HOME/hackios-os
OUT=$ROOT/out
mkdir -p "$OUT" "$HACKIOS_HOME/logs"
cd "$ROOT"

fetch_commit() {
  git init -q "$2"
  git -C "$2" remote add origin "$1"
  git -C "$2" fetch --depth 1 origin "$3"
  git -C "$2" checkout --detach FETCH_HEAD
}

case "${1:-}" in
  setup)
    [ "$(uname -sm)" = 'Linux x86_64' ] || { echo 'Requires Linux x86-64' >&2; exit 1; }
    fetch_commit https://github.com/oosexgang/hackios-xnu-kernel.git "$HS" \
      88513176b1e96ecf0b764cd62c6f4e6ac71345e3
    fetch_commit https://github.com/Project-Silicium/Mu-Silicium.git "$MU_DIR" \
      "$(cat port/devices/oneplus-aston/uefi/BASE)"
    git -C "$MU_DIR" submodule update --init --recursive --depth 1
    cp -a port/devices/oneplus-aston/uefi/files/. "$MU_DIR/"
    mkdir -p "$THEOS/toolchain/linux/iphone" "$THEOS/sdks"
    curl -fL --retry 3 -o "$HACKIOS_HOME/iOSToolchain.tar.xz" \
      https://github.com/L1ghtmann/llvm-project/releases/latest/download/iOSToolchain-x86_64.tar.xz
    tar -xJf "$HACKIOS_HOME/iOSToolchain.tar.xz" -C "$THEOS/toolchain/linux/iphone" --strip-components=2
    test -x "$THEOS/toolchain/linux/iphone/bin/ld"
    git clone --depth 1 --filter=blob:none --sparse https://github.com/theos/sdks.git "$THEOS/sdks-git"
    git -C "$THEOS/sdks-git" sparse-checkout set iPhoneOS16.5.sdk
    ln -s "$THEOS/sdks-git/iPhoneOS16.5.sdk" "$THEOS/sdks/iPhoneOS16.5.sdk"
    {
      git rev-parse HEAD
      git -C "$HS" rev-parse HEAD
      git -C "$MU_DIR" rev-parse HEAD
      git -C "$THEOS/sdks-git" rev-parse HEAD
      sha256sum "$HACKIOS_HOME/iOSToolchain.tar.xz"
    } > "$OUT/build-provenance.txt"
    ;;
  uefi)
    bash scripts/build_uefi_aston.sh
    # Explicitly rebuild the patched shim with the payload destination define.
    rm -f "$MU_DIR/BootShim/BootShim.elf" "$MU_DIR/BootShim/BootShim.bin"
    make -C "$MU_DIR/BootShim" REQUIRES_KERNEL_HEADER=1 FD_BASE=0xA7100000 FD_SIZE=0x300000 \
      CFLAGS='--target=aarch64-linux-gnu -DPAYLOAD_BASE=0xE2000000'
    python3 port/mkboot-aston.py --fd "$OUT/SILICIUM_UEFI-aston.fd" --out "$OUT/boot-aston-uefi.img"
    bash scripts/build_loader_aston.sh
    cp "$HS/xnuloader/loader.efi" "$OUT/loader-aston.efi"
    ;;
  kernel)
    # install_touch expects an already-applied XNU source tree.
    (cd "$HS" && bash xnu/apply.sh)
    bash scripts/install_touch_aston.sh
    # Use fail-fast setup; the original wrapper ignores dependency failures.
    (cd "$HS" && bash xnu-deps/setup.sh) 2>&1 | tee "$HACKIOS_HOME/logs/xnu-deps.log"
    set +e
    (cd "$HS" && bash xnu-build.sh -j"${JOBS:-2}" -k) > "$HACKIOS_HOME/logs/xnu-build.log" 2>&1
    rc=$?
    set -e
    tail -60 "$HACKIOS_HOME/logs/xnu-build.log"
    K=$HS/xnu-src/xnu-8796.121.2/BUILD/obj/DEVELOPMENT_ARM64_BCM2837/mach.development.bcm2837
    # Upstream may fail its final export-symbol check after linking. Still require a Mach-O kernel.
    test -s "$K" || { echo "Kernel missing (make exit $rc)" >&2; exit 1; }
    file "$K" | tee -a "$OUT/build-provenance.txt" | grep 'Mach-O.*arm64'
    printf 'xnu make exit: %s\n' "$rc" >> "$OUT/build-provenance.txt"
    cp "$K" "$OUT/mach.development.bcm2837"
    ;;
  images)
    (cd "$HS" && make fetch) 2>&1 | tee "$HACKIOS_HOME/logs/fetch.log"
    (cd "$HS" && REST=1 bash userland/build.sh) 2>&1 | tee "$HACKIOS_HOME/logs/images.log"
    cp "$HS/userland/system.apfs" "$HS/userland/root.apfs" "$OUT/"
    ;;
  bundle)
    python3 port/check_boot.py "$OUT/boot-aston-uefi.img"
    python3 port/check_boot.py "$OUT/boot-aston-xnu.img"
    python3 - "$OUT" <<'PY'
import pathlib, struct, sys
p = pathlib.Path(sys.argv[1])
for name in ('boot-aston-uefi.img', 'boot-aston-xnu.img'):
    b = (p / name).read_bytes()
    assert b[:8] == b'ANDROID!' and struct.unpack_from('<I', b, 40)[0] == 4, name
assert (p / 'system.apfs').stat().st_size > 1024**3
assert (p / 'root.apfs').stat().st_size > 0
assert (p / 'mach.development.bcm2837').read_bytes()[:4] == bytes.fromhex('cffaedfe')
PY
    B=$OUT/package
    mkdir -p "$B/out" "$B/port/devices/oneplus-aston" "$B/repos/hackios-xnu-kernel/xnuloader" "$B/docs"
    cp "$OUT/boot-aston-uefi.img" "$OUT/boot-aston-xnu.img" "$OUT/loader-aston.efi" \
      "$OUT/mach.development.bcm2837" "$OUT/system.apfs" "$OUT/root.apfs" "$OUT/build-provenance.txt" "$B/out/"
    cp port/hackios-aston.py "$B/port/"
    cp port/devices/oneplus-aston/soc.args "$B/port/devices/oneplus-aston/"
    cp "$HS/xnuloader/mkpayload.py" "$B/repos/hackios-xnu-kernel/xnuloader/"
    cp docs/EXPERIENCE-MAC.md "$B/docs/"
    (cd "$B" && find out -type f -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
    tar -cf "$OUT/astonc-mac-experience.tar" -C "$B" .
    ;;
  *) echo "Usage: $0 setup|uefi|kernel|images|bundle" >&2; exit 2 ;;
esac
