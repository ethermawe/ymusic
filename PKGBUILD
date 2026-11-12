# Maintainer: ethermawe
pkgname=ymusic
pkgver=0.1.0
pkgrel=1
pkgdesc="Нативный клиент Яндекс Музыки на Rust и Qt Quick"
arch=('x86_64')
url="https://github.com/ethermawe/ymusic"
license=('custom')
depends=('alsa-lib' 'qt6-base' 'qt6-declarative' 'hicolor-icon-theme')
makedepends=('cargo' 'cmake' 'qt6-shadertools')
provides=('ymusic')
conflicts=('ymusic-git')
options=('!lto')

build() {
    cd "$startdir"
    cargo build --release --locked --lib
    cmake -S src-qt -B build-qt -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr
    cmake --build build-qt
}

package() {
    cd "$startdir"
    DESTDIR="$pkgdir" cmake --install build-qt
}
