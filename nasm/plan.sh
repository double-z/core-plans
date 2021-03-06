pkg_name=nasm
pkg_distname=$pkg_name
pkg_origin=core
pkg_version=2.12.02
pkg_description="The Netwide Assembler, NASM, is an 80x86 and x86-64 assembler designed for portability and modularity."
pkg_upstream_url=http://www.nasm.us/
pkg_maintainer="The Habitat Maintainers <humans@habitat.sh>"
pkg_license=('BSD-2-Clause')
pkg_source=http://www.nasm.us/pub/$pkg_distname/releasebuilds/${pkg_version}/$pkg_distname-${pkg_version}.tar.bz2
pkg_shasum=00b0891c678c065446ca59bcee64719d0096d54d6886e6e472aeee2e170ae324
pkg_deps=(core/glibc)
pkg_build_deps=(core/gcc core/make)
pkg_bin_dirs=(bin)
