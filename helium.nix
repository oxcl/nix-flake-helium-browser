{ lib
, stdenv
, fetchurl
, dpkg
, patchelf
, makeWrapper
, wrapGAppsHook3
, qt6
, glib
, gsettings-desktop-schemas
, gtk3
, gtk4
, adwaita-icon-theme
, nss
, nspr
, libGL
, libgbm
, libdrm
, libxkbcommon
, libX11
, libXcomposite
, libXdamage
, libXext
, libXfixes
, libXrandr
, libXrender
, libxcb
, libxshmfence
, libXi
, libXcursor
, libXft
, libXScrnSaver
, libXtst
, libSM
, libICE
, alsa-lib
, dbus
, cups
, ffmpeg
, libva
, pipewire
, wayland
, vulkan-loader
, systemd
, xdg-utils
, coreutils
, pango
, cairo
, gdk-pixbuf
, atk
, at-spi2-atk
, at-spi2-core
, freetype
, fontconfig
, libuuid
, expat
, zlib
, libxml2
, libkrb5
, snappy
, udev
, libXt
, binutils
}:

let
  pname = "helium";
  version = "0.11.7.1";

  suffix = {
    aarch64-linux = "arm64";
    x86_64-linux = "amd64";
  }.${stdenv.hostPlatform.system} or (throw "Unsupported system: ${stdenv.hostPlatform.system}");

  src = fetchurl {
    url = "https://github.com/imputnet/helium-linux/releases/download/${version}/helium-bin_${version}-1_${suffix}.deb";
    sha256 = "sha256-nW7Q4diGoqB7W5XUXHhvf0EVtcD9lyyXDZrb4ftab0o=";
  };

  inherit (lib) optional optionals makeLibraryPath makeSearchPathOutput makeBinPath;

  deps = [
    stdenv.cc.cc
    nss
    nspr
    libGL
    libgbm
    libdrm
    libxkbcommon
    libX11
    libXcomposite
    libXdamage
    libXext
    libXfixes
    libXrandr
    libXrender
    libxcb
    libxshmfence
    libXi
    libXcursor
    libXft
    libXScrnSaver
    libXtst
    libSM
    libICE
    alsa-lib
    dbus
    cups
    ffmpeg
    libva
    pipewire
    wayland
    vulkan-loader
    systemd
    pango
    cairo
    gdk-pixbuf
    atk
    at-spi2-atk
    at-spi2-core
    freetype
    fontconfig
    libuuid
    expat
    zlib
    libxml2
    gtk3
    glib
    libXt
    libkrb5
    snappy
    udev
  ];

  libPath = makeLibraryPath deps
    + lib.optionalString (stdenv.hostPlatform.is64bit)
      (":" + makeSearchPathOutput "lib" "lib64" deps)
    + ":$out/opt/helium";

  binpath = makeBinPath deps;
in

stdenv.mkDerivation {
  inherit pname version src;

  dontConfigure = true;
  dontBuild = true;
  dontPatchELF = true;
  dontStrip = true;

  nativeBuildInputs = [
    patchelf
    makeWrapper
    wrapGAppsHook3
    qt6.wrapQtAppsHook
    dpkg
    binutils
  ];

  dontWrapQtApps = true;

  buildInputs = [
    glib
    gsettings-desktop-schemas
    gtk3
    gtk4
    adwaita-icon-theme
    qt6.qtbase
    qt6.qtwayland
    libXt
    libkrb5
    snappy
    udev
    systemd
  ];

  unpackPhase = ''
    runHook preUnpack
    ar vx $src
    tar -xvf data.tar.xz
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out $out/bin $out/opt

    cp -r opt/helium $out/opt/helium
    cp -r usr/share $out/share

    # Patch main binaries
    patchelf \
      --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
      --set-rpath "${libPath}" \
      $out/opt/helium/helium

    patchelf \
      --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
      --set-rpath "${libPath}" \
      $out/opt/helium/helium_crashpad_handler

    # Patch shared libraries that need it
    for lib in $out/opt/helium/libEGL.so $out/opt/helium/libGLESv2.so; do
      if [ -f "$lib" ]; then
        patchelf --set-rpath "${libPath}" "$lib" || true
      fi
    done

    # Fix the upstream wrapper script to use the correct binary path
    substituteInPlace $out/opt/helium/helium-wrapper \
      --replace-fail '$HERE/helium' "$out/opt/helium/helium"

    # Create symlink for wrapGAppsHook to wrap (like Brave does)
    ln -sf $out/opt/helium/helium-wrapper $out/bin/helium

    # Fix .desktop file
    substituteInPlace $out/share/applications/helium.desktop \
      --replace-fail 'Exec=helium' "Exec=$out/bin/helium" \
      --replace-fail 'Icon=helium' "Icon=$out/share/icons/hicolor/256x256/apps/helium.png"

    # Copy icon to hicolor theme directory
    mkdir -p $out/share/icons/hicolor/256x256/apps
    if [ -f $out/opt/helium/product_logo_256.png ]; then
      cp $out/opt/helium/product_logo_256.png $out/share/icons/hicolor/256x256/apps/helium.png
    elif [ -f $out/opt/helium/product_logo.png ]; then
      cp $out/opt/helium/product_logo.png $out/share/icons/hicolor/256x256/apps/helium.png
    fi

    runHook postInstall
  '';

  preFixup = ''
    gappsWrapperArgs+=(
      --prefix LD_LIBRARY_PATH : "${libPath}"
      --prefix PATH : ${lib.makeBinPath [ xdg-utils coreutils ]}
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto}}"
      --set-default CHROME_VERSION_EXTRA nix
    )
  '';

  meta = {
    homepage = "https://helium.computer";
    description = "Private, fast, and honest web browser based on Chromium";
    license = lib.licenses.gpl3Only;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    maintainers = [ ];
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    mainProgram = "helium";
  };
}
