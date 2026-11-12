# Maintainer: ethermawe
pkgname=ymusic
pkgver=0.1.0
pkgrel=3
pkgdesc="Нативный клиент Яндекс Музыки на Rust и Qt Quick"
arch=('x86_64')
url="https://github.com/ethermawe/ymusic"
license=('custom')
depends=('alsa-lib' 'gcc-libs' 'glibc' 'qt6-base' 'qt6-declarative' 'qt6-svg' 'hicolor-icon-theme')
makedepends=('cmake' 'ninja' 'pkgconf' 'qt6-shadertools')
if ! command -v cargo >/dev/null 2>&1; then
    makedepends+=('cargo')
fi
optdepends=('xdg-utils: открытие страницы входа и папки загрузок')
conflicts=('ymusic-git')
options=('!lto' '!debug')
# makepkg normally uses ./src, which is already our Rust source directory.
if [[ ${BUILDDIR:-$startdir} -ef "$startdir" ]]; then
    BUILDDIR="$startdir/build-makepkg"
fi
# Local-checkout recipe: run makepkg from the repository root.
# Do not use an unpushed release archive or include target/.git in sources.
source=('Cargo.toml' 'Cargo.lock' 'ymusic.desktop' 'icon.svg')
sha256sums=('SKIP' 'SKIP' 'SKIP' 'SKIP')

prepare() {
    mkdir -p "$srcdir/ymusic"
    cp -a "$startdir/src" "$startdir/src-qt" "$startdir/icons" "$srcdir/ymusic/"
    cp "$srcdir/Cargo.toml" "$srcdir/Cargo.lock" \
        "$srcdir/ymusic.desktop" "$srcdir/icon.svg" "$srcdir/ymusic/"
    cd "$srcdir/ymusic"
    export CARGO_TARGET_DIR="$srcdir/ymusic/target"
    cargo fetch --locked
}

build() {
    cd "$srcdir/ymusic"
    export CARGO_TARGET_DIR="$srcdir/ymusic/target"
    export CARGO_INCREMENTAL=0
    cargo build --release --frozen --lib
    cmake -S src-qt -B build-qt -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_INSTALL_LIBDIR=lib
    cmake --build build-qt
}

check() {
    cd "$srcdir/ymusic"
    export CARGO_TARGET_DIR="$srcdir/ymusic/target"
    export CARGO_INCREMENTAL=0
    # Keep tests away from the user's real downloads and settings.
    mkdir -p "$srcdir/test-data" "$srcdir/test-config"
    XDG_DATA_HOME="$srcdir/test-data" XDG_CONFIG_HOME="$srcdir/test-config" \
        cargo test --release --frozen --lib
}

package() {
    cd "$srcdir/ymusic"
    DESTDIR="$pkgdir" cmake --install build-qt
}
