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
              #!/usr/bin/env bash
              exec ${pkgs.quickshell}/bin/qs -p "$out/share/island-dots" "\$@"
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
