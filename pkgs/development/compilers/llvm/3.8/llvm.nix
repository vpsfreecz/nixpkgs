{ stdenv
, fetch
, fetchpatch
, perl
, groff
, cmake
, python
, libffi
, libbfd
, libxml2
, valgrind
, ncurses
, version
, zlib
, compiler-rt_src
, libcxxabi
, debugVersion ? false
, enableSharedLibraries ? true
}:

let
  src = fetch "llvm" "1ybmnid4pw2hxn12ax5qa5kl1ldfns0njg8533y3mzslvd5cx0kf";
in stdenv.mkDerivation rec {
  name = "llvm-${version}";

  unpackPhase = ''
    unpackFile ${src}
    mv llvm-${version}.src llvm
    sourceRoot=$PWD/llvm
    unpackFile ${compiler-rt_src}
    mv compiler-rt-* $sourceRoot/projects/compiler-rt
  '';

  buildInputs = [ perl groff cmake libxml2 python libffi ]
    ++ stdenv.lib.optional stdenv.isDarwin libcxxabi;

  propagatedBuildInputs = [ ncurses zlib ];

  # Fix a segfault in llc
  # See http://lists.llvm.org/pipermail/llvm-dev/2016-October/106500.html
  patches = [ ./D17533-1.patch ] ++
    stdenv.lib.optionals (!stdenv.isDarwin) [./fix-llvm-config.patch];

  # hacky fix: New LLVM releases require a newer macOS SDK than
  # 10.9. This is a temporary measure until nixpkgs darwin support is
  # updated.
  postPatch = stdenv.lib.optionalString stdenv.isDarwin ''
    sed -i 's/os_trace(\(.*\)");$/printf(\1\\n");/g' ./projects/compiler-rt/lib/sanitizer_common/sanitizer_mac.cc

    substituteInPlace CMakeLists.txt \
      --replace 'set(CMAKE_INSTALL_NAME_DIR "@rpath")' "set(CMAKE_INSTALL_NAME_DIR "$out/lib")" \
      --replace 'set(CMAKE_INSTALL_RPATH "@executable_path/../lib")' ""
  ''
  + stdenv.lib.optionalString (stdenv ? glibc) ''
    (
      cd projects/compiler-rt
      patch -p1 < ${
        fetchpatch {
          name = "sigaltstack.patch"; # for glibc-2.26
          url = https://github.com/llvm-mirror/compiler-rt/commit/8a5e425a68d.diff;
          sha256 = "0h4y5vl74qaa7dl54b1fcyqalvlpd8zban2d1jxfkxpzyi7m8ifi";
        }
      }
    )
  '';

  # hacky fix: created binaries need to be run before installation
  preBuild = ''
    mkdir -p $out/
    ln -sv $PWD/lib $out
  '';

  cmakeFlags = with stdenv; [
    "-DCMAKE_BUILD_TYPE=${if debugVersion then "Debug" else "Release"}"
    "-DLLVM_INSTALL_UTILS=ON"  # Needed by rustc
    "-DLLVM_BUILD_TESTS=ON"
    "-DLLVM_ENABLE_FFI=ON"
    "-DLLVM_ENABLE_RTTI=ON"
  ] ++ stdenv.lib.optional enableSharedLibraries [
    "-DLLVM_LINK_LLVM_DYLIB=ON"
  ] ++ stdenv.lib.optional (!isDarwin)
    "-DLLVM_BINUTILS_INCDIR=${libbfd.dev}/include"
    ++ stdenv.lib.optionals ( isDarwin) [
    "-DLLVM_ENABLE_LIBCXX=ON"
    "-DCAN_TARGET_i386=false"
  ];

  postBuild = ''
    rm -fR $out

    paxmark m bin/{lli,llvm-rtdyld}
  '';

  postInstall = stdenv.lib.optionalString (stdenv.isDarwin && enableSharedLibraries) ''
    ln -s $out/lib/libLLVM.dylib $out/lib/libLLVM-${version}.dylib
  '';

  enableParallelBuilding = true;

  passthru.src = src;

  meta = {
    description = "Collection of modular and reusable compiler and toolchain technologies";
    homepage    = http://llvm.org/;
    license     = stdenv.lib.licenses.ncsa;
    maintainers = with stdenv.lib.maintainers; [ lovek323 raskin viric ];
    platforms   = stdenv.lib.platforms.all;
  };
}
