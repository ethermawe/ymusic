# Maintainer: ethermawe
pkgname=ymusic
pkgver=0.1.0
pkgrel=1
pkgdesc="Лёгкий нативный клиент Яндекс Музыки на Rust и Slint"
arch=('x86_64')
url="https://github.com/ethermawe/ymusic"
license=('custom')
depends=('alsa-lib' 'fontconfig' 'freetype2' 'hicolor-icon-theme' 'libxkbcommon')
makedepends=('cargo')
provides=('ymusic')
conflicts=('ymusic-git')
options=('!lto')

build() {
    cd "$startdir"
    cargo build --release --locked
}

package() {
    cd "$startdir"
    install -Dm755 "target/release/ymusic" "$pkgdir/usr/bin/ymusic"
    install -Dm644 "ymusic.desktop" "$pkgdir/usr/share/applications/ymusic.desktop"
    install -Dm644 "icon.svg" "$pkgdir/usr/share/icons/hicolor/scalable/apps/ymusic.svg"
}
