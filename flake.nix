{
  description = "Zig project flake";

  inputs = {
    zig2nix.url = "github:Cloudef/zig2nix";
  };

  outputs = { zig2nix, ... }: let
    flake-utils = zig2nix.inputs.flake-utils;
  in (flake-utils.lib.eachDefaultSystem (system: let
        env = zig2nix.outputs.zig-env.${system} {
                enableVulkan = true;
        };

        system-triple = env.lib.zigTripleFromString system;

        wgpu-native = env.pkgs.rustPlatform.buildRustPackage rec {
                pname = "wgpu-native";
                version = "0.19.4.1";

                src = env.pkgs.fetchFromGitHub {
                    owner = "gfx-rs";
                    repo = "wgpu-native";
                    rev = "v${version}";
                    hash = "sha256-pfgfJfE5KFfI0aEdMIhfhPd/ZweT040IFyB51h12vN8=";
                    fetchSubmodules = true;
                };

                cargoHash = "";
                
                nativeBuildInputs = [ env.pkgs.llvmPackages.clang ];

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

            LIBCLANG_PATH = "${env.pkgs.llvmPackages.libclang.lib}/lib";
        };
    in with builtins; with env.lib; with env.pkgs.lib; rec {
      # nix build .#target.{zig-target}
      # e.g. nix build .#target.x86_64-linux-gnu
      packages.target = genAttrs allTargetTriples (target: env.packageForTarget target ({
        src = cleanSource ./.;

        nativeBuildInputs = with env.pkgs; [];
        buildInputs = with env.pkgsForTarget target; [];

        preBuild = ''
            mkdir -p /build/source/wgpu_native
            cp ${wgpu-native.out}/lib/* /build/source/wgpu_native
        '';

        LD_LIBRARY_PATH = "${env.pkgs.mesa_drivers.out}/lib:${env.pkgs.libglvnd.out}/lib:$LD_LIBRARY_PATH";

        zigPreferMusl = true;
        zigDisableWrap = true;
      } // optionalAttrs (!pathExists ./build.zig.zon) {
        pname = "my-zig-project";
        version = "0.0.0";
      }));

      # nix build .
      packages.default = packages.target.${system-triple}.override {
        zigPreferMusl = false;
        zigDisableWrap = false;
      };

      # For bundling with nix bundle for running outside of nix
      # example: https://github.com/ralismark/nix-appimage
      apps.bundle.target = genAttrs allTargetTriples (target: let
        pkg = packages.target.${target};
      in {
        type = "app";
        program = "${pkg}/bin/default";
      });

      # default bundle
      apps.bundle.default = apps.bundle.target.${system-triple};

      # nix develop
      devShells.default = env.mkShell {};
    }));
}
