{ pkgs ? import <nixpkgs> {} }:

if pkgs ? mkShellNoCC then
  pkgs.mkShellNoCC {
    packages = with pkgs; [
      quickshell
      jq
      python3
      bash
    ];

    shellHook = ''
      echo "island-dots dev shell"
      echo "run: qs -c island -n -d"
    '';
  }
else
  pkgs.mkShell {
    packages = with pkgs; [
      quickshell
      jq
      python3
      bash
    ];
  }
