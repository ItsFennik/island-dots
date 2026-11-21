{
  description = "Island - a macOS-style Wayland desktop shell built on Quickshell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = self.packages.${system}.island-dots;
          island-dots = pkgs.stdenvNoCC.mkDerivation {
            pname = "island-dots";
            version = "unstable";
            src = pkgs.lib.cleanSource ./.;

            installPhase = ''
              runHook preInstall
              mkdir -p $out/share/island-dots
              cp -r . $out/share/island-dots
              mkdir -p $out/bin
              cat > $out/bin/island <<WRAP
              #!/bin/sh
              cfg="\${XDG_CONFIG_HOME:-\$HOME/.config}/quickshell"
              mkdir -p "\$cfg"
              if [ -e "\$cfg/island" ] && [ ! -L "\$cfg/island" ]; then
                echo "island: \$cfg/island exists and is not a symlink; move it away first" >&2
                exit 1
              fi
              ln -sfn "$out/share/island-dots" "\$cfg/island"
              exec ${pkgs.quickshell}/bin/qs -c island "\$@"
              WRAP
              chmod +x $out/bin/island
              runHook postInstall
            '';

            meta = with pkgs.lib; {
              description = "Island - a macOS-style Wayland desktop shell built on Quickshell";
              homepage = "https://github.com/ItsFennik/island-dots";
              platforms = platforms.linux;
            };
          };
        });

      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShellNoCC {
            packages = with pkgs; [
              quickshell
              jq
              python3
              bash
              git
            ];

            shellHook = ''
              echo "island-dots dev shell"
              echo "run: qs -c island -n -d"
            '';
          };
        });
    };
}
