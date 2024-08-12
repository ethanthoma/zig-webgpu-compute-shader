{
  description = "Zig project flake";

  inputs = {
    zig2nix.url = "github:Cloudef/zig2nix";
  };

  outputs = { zig2nix, ... }:
    let
      flake-utils = zig2nix.inputs.flake-utils;
    in
    (flake-utils.lib.eachDefaultSystem (system:
      let
        env = zig2nix.outputs.zig-env.${system} {
          enableVulkan = true;
          enableOpenGL = true;
          enableWayland = true;
        };

        system-triple = env.lib.zigTripleFromString system;
      in
      with builtins; with env.lib; with env.pkgs.lib; rec {
        # nix build .#target.{zig-target}
        # e.g. nix build .#target.x86_64-linux-gnu
        packages.target = genAttrs allTargetTriples (target: env.packageForTarget target (
          let
            pkgs = env.pkgsForTarget target;

            waylandSupport = true;
            x11Support = false;

            wgpu-native = pkgs.rustPlatform.buildRustPackage rec {
              pname = "wgpu-native";
              version = "0.19.4.1";

              src = pkgs.fetchFromGitHub {
                owner = "gfx-rs";
                repo = "wgpu-native";
                rev = "v${version}";
                hash = "sha256-pfgfJfE5KFfI0aEdMIhfhPd/ZweT040IFyB51h12vN8=";
                fetchSubmodules = true;
              };

              cargoHash = "";

              nativeBuildInputs = [ pkgs.llvmPackages.clang ];

              cargoLock = {
                lockFile = "${src}/Cargo.lock";
                outputHashes = {
                  "d3d12-0.19.0" = "sha256-fTrkhrGZ80mJYF2QfHlRikP7xNns+MfQpF65zWmXpk4=";
                };
              };

              postInstall = ''
                cp $src/ffi/wgpu.h $out/lib
                ls $src/ffi
                cp $src/ffi/webgpu-headers/webgpu.h $out/lib
              '';

              LIBCLANG_PATH = "${pkgs.llvmPackages.libclang.lib}/lib";
            };

            glfw3 =
              let
                waylandCmakeFlag = if waylandSupport then [ "-DGLFW_BUILD_WAYLAND=ON" ] else [ "-DGLFW_BUILD_WAYLAND=OFF" ];
                x11CmakeFlag = if x11Support then [ "-DGLFW_BUILD_X11=ON" ] else [ "-DGLFW_BUILD_X11=OFF" ];
              in
              pkgs.stdenv.mkDerivation rec {
                name = "glfw3";
                version = "3.4";

                cmakeFlags = [
                  waylandCmakeFlag
                  x11CmakeFlag
                  "-DCMAKE_CXX_FLAGS=-I${pkgs.libGL.dev}/include"
                  "-DCMAKE_LD_FLAGS=-L${pkgs.libGL.out}/lib"
                ];

                buildInputs = [ ] ++ pkgs.lib.optionals waylandSupport (with pkgs; [
                  wayland
                  libxkbcommon
                  libffi
                  wayland-scanner
                  wayland-protocols
                ]);

                nativeBuildInputs = with pkgs; [
                  pkg-config
                  cmake
                ];

                src = pkgs.fetchFromGitHub {
                  owner = name;
                  repo = name;
                  rev = version;
                  hash = "sha256-FcnQPDeNHgov1Z07gjFze0VMz2diOrpbKZCsI96ngz0=";
                };
              };
          in
          {
            src = cleanSource ./.;

            buildInputs = with pkgs; [ wayland.dev ];

            prePatch = ''
              substituteInPlace /build/source/build.zig \
              --replace-fail '@libGL@' "${pkgs.libGL.dev}/include" \
              --replace-fail '@libwayland@' "${pkgs.wayland.dev}/include"
            '';

            # this should be improved
            preBuild = ''
              mkdir -p /build/source/wgpu_native
              cp ${wgpu-native.out}/lib/* /build/source/wgpu_native

              mkdir -p /build/source/glfw3
              cp ${glfw3}/lib/libglfw3.a /build/source/glfw3
              cp ${glfw3}/include/GLFW/* /build/source/glfw3

              ls ${pkgs.wayland.dev}/include
            '';

            zigPreferMusl = true;
            zigDisableWrap = true;
          }
        ));

        # nix build .
        packages.default = packages.target.${system-triple}.override {
          zigPreferMusl = false;
          zigDisableWrap = false;
        };

        # For bundling with nix bundle for running outside of nix
        # example: https://github.com/ralismark/nix-appimage
        apps.bundle.target = genAttrs allTargetTriples (target:
          let
            pkg = packages.target.${target};
          in
          {
            type = "app";
            program = "${pkg}/bin/default";
          });

        # default bundle
        apps.bundle.default = apps.bundle.target.${system-triple};

        # nix develop
        devShells.default = env.mkShell { };
      }));
}
