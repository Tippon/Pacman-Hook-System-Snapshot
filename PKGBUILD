# Maintainer: 7thCore <the7thcore@gmail.com>

pkgname=pacman-hook-system-snapshot
pkgver=1.2
pkgrel=9
pkgdesc='Pacman hook to create bootable system snasphots using btrfs and systemd-boot'
arch=('any')
depends=('bash' 'btrfs-progs')
backup=('etc/core-repo/system-snapshot.conf')
source=('05-system-snapshot.hook'
        'system-snapshot.sh'
        'system-snapshot.conf'
        'system-snapshot.service'
        'system-snapshot.timer'
        'vfat.conf')
sha256sums=('47af0c430841c0944ea36040b50fc88b44c92d914cc835110026aa895388c377'
            '942152f7753d3a5d64b20f6eb72bfd8598e205aeb1381ddc78909c15365eb903'
            '92041e98996b5243f39ef456b124140e645515227b13f3ca8794e325b059b1ce'
            '79998c9e8184e1e12e27d0e226acacd455ba8dda03d4860b723791b9ece5907d'
            'e5f001557c0b7c1620686b0db1e524356f2269782af7a89fe0c5b56c5360df48'
            '98d55654e0c2a7c5d545240d0403dd12c9b7e71f90a915ec9b68a6a0f81d0b48')

package() {
  install -d -m0755 "/etc/core-repo"
  install -d -m0755 "${pkgdir}/usr/bin"
  install -D -m0644 "${srcdir}/05-system-snapshot.hook" "${pkgdir}/usr/share/libalpm/hooks/05-system-snapshot.hook"
  install -D -Dm755 "${srcdir}/system-snapshot.sh" "${pkgdir}/usr/share/libalpm/scripts/system-snapshot.sh"
  install -D -m0644 "${srcdir}/system-snapshot.conf" "${pkgdir}/etc/core-repo/system-snapshot.conf"
  install -D -m0644 "${srcdir}/system-snapshot.service" "${pkgdir}/usr/lib/systemd/system-snapshot.service"
  install -D -m0644 "${srcdir}/system-snapshot.timer" "${pkgdir}/usr/lib/systemd/system-snapshot.timer"
  install -D -m0644 "${srcdir}/vfat.conf" "${pkgdir}/usr/lib/modules-load.d/vfat.conf"
  ln -s /usr/share/libalpm/scripts/system-snapshot.sh "${pkgdir}"/usr/bin/system-snapshot
}
