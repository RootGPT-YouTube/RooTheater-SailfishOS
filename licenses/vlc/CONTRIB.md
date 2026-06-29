# libVLC contrib libraries — license mapping

To support HTTPS network streaming, RooTheater's bundled libVLC 3.0.21 includes
the TLS access plugin (`libgnutls_plugin.so`) and the MPEG-TS demux plugin
(`libts_plugin.so`). These plugins are built by VLC's contrib system (see
`scripts/build-libvlc.sh`) and **statically** link the libraries below — no
separate shared objects are shipped. Each is used under the terms of its license;
the full texts are in this directory.

| Library   | Version | License                                   | Text in this dir      | Upstream |
|-----------|---------|-------------------------------------------|-----------------------|----------|
| GnuTLS    | 3.6.16  | LGPL-2.1-or-later                         | `COPYING.LGPLv2.1`    | https://www.gnutls.org/ |
| Nettle    | 3.7.3   | LGPL-3.0-or-later OR GPL-2.0-or-later     | `COPYING.LGPLv3` / `COPYING.GPLv2` | https://www.lysator.liu.se/~nisse/nettle/ |
| GMP       | 6.1.2   | LGPL-3.0-or-later OR GPL-2.0-or-later     | `COPYING.LGPLv3` / `COPYING.GPLv2` | https://gmplib.org/ |
| libtasn1  | 4.8     | LGPL-2.1-or-later                         | `COPYING.LGPLv2.1`    | https://www.gnu.org/software/libtasn1/ |
| libdvbpsi | 1.3.3   | LGPL-2.1-or-later                         | `COPYING.LGPLv2.1`    | https://www.videolan.org/developers/libdvbpsi.html |

Corresponding source: the upstream projects at the versions above, reproducible
with `scripts/build-libvlc.sh` (which drives the VLC contrib download + build).
