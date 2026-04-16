# Copyright 2026 ResQ
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Skeleton flake for ResQ repos — copy and extend the `devPackages` list.
# Inputs and shellHook are intentionally project-agnostic.

{
  description = "ResQ - Resilient Disaster Response & Critical Delivery Infrastructure";

  inputs = {
    nixpkgs.url      = "github:nixos/nixpkgs/nixos-25.11";
    flake-utils.url  = "github:numtide/flake-utils";
    rust-overlay.url = "github:oxalica/rust-overlay";
  };

  outputs =
    { self, nixpkgs, flake-utils, rust-overlay, ... }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      mkDevShell = pkgs: system:
        let
          # Each repo extends this list with its own toolchain.
          devPackages = with pkgs;
            builtins.filter (p: p != null) [
              git
              git-lfs
            ];

          shellHook = ''
            set -e

            echo "--- ResQ Polyglot Environment (${system}) ---"
            echo "Channel: nixos-24.11"

            version_check() {
              local cmd="$1"
              local name="$2"
              if command -v "$cmd" >/dev/null 2>&1; then
                local version
                version=$("$cmd" --version 2>/dev/null | head -n 1 | sed 's/^[vV]//' | xargs || echo "active")
                [ -z "$version" ] && version="active"
                echo "$name: $version"
                return 0
              else
                echo "$name: NOT FOUND"
                return 1
              fi
            }

            version_check "git" "Git"

            echo "--------------------------------"

            if [[ "$OSTYPE" == "darwin"* ]]; then
              echo "Note: .NET and ROS2 are not available on macOS"
            fi
          '';
        in
        {
          default = pkgs.mkShell {
            packages = devPackages;
            inherit shellHook;

            buildInputs = with pkgs;
              lib.optionals stdenv.isLinux [
                pkg-config
                openssl
              ] ++ lib.optionals stdenv.isDarwin [
                darwin.apple_sdk.frameworks.Security
                darwin.apple_sdk.frameworks.CoreFoundation
              ];
          };
        };
    in
    flake-utils.lib.eachSystem supportedSystems (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ rust-overlay.overlays.default ];
          config = {
            allowUnfree = true;
            # Do not allow insecure packages by default.
            permittedInsecurePackages = [ ];
          };
        };
      in
      {
        formatter = pkgs.alejandra or pkgs.nixpkgs-fmt;
        devShells = mkDevShell pkgs system;
      }
    );
}
