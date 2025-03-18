{
  description = "Haskell TMDB Data Fetcher";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Haskell package
        haskellPackages = pkgs.haskellPackages;

        # Project source
        tmdbFetcherSrc = ./.;

        # Default output path
        defaultOutputPath = "./output";

        # Helper script to run the fetcher
        tmdb-fetcher-script = pkgs.writeShellScriptBin "tmdb-fetcher" ''
          # Make zlib available at runtime
          export LD_LIBRARY_PATH=${pkgs.zlib}/lib:$LD_LIBRARY_PATH

          set -e

          if [ -z "$TMDB_API_KEY" ]; then
            echo "Error: TMDB_API_KEY environment variable is not set."
            echo "Please set it to your TMDB API key."
            echo "Example: export TMDB_API_KEY=your_api_key_here"
            exit 1
          fi

          # Default output path if none provided
          OUTPUT_PATH=''${1:-"${defaultOutputPath}/movies.json"}

          # Ensure directory exists
          mkdir -p "$(dirname "$OUTPUT_PATH")"

          echo "Fetching movie data from TMDB..."
          ${self.packages.${system}.default}/bin/tmdb-fetcher "$OUTPUT_PATH"

          echo "Movie data saved to $OUTPUT_PATH"
        '';

      in {
        # The standalone package
        packages.default = haskellPackages.callCabal2nix "tmdb-fetcher" tmdbFetcherSrc {
          # Add native dependencies that the Haskell packages need
          zlib = pkgs.zlib;
        };

        # App that can be run with `nix run`
        apps.default = {
          type = "app";
          program = "${tmdb-fetcher-script}/bin/tmdb-fetcher";
        };

        # Development shell
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Haskell development tools
            haskellPackages.cabal-install
            haskellPackages.ghc
            haskellPackages.cabal-fmt
            haskellPackages.hlint
            haskellPackages.haskell-language-server

            # System dependencies
            zlib zlib.dev

            # Additional libraries that might be useful
            haskellPackages.aeson
            haskellPackages.http-conduit
            haskellPackages.bytestring
          ];

          # Set up environment variables for C libraries
          shellHook = ''
            # Make zlib available
            export LD_LIBRARY_PATH=${pkgs.zlib}/lib:$LD_LIBRARY_PATH
            export LIBRARY_PATH=${pkgs.zlib}/lib:$LIBRARY_PATH
            export C_INCLUDE_PATH=${pkgs.zlib.dev}/include:$C_INCLUDE_PATH
            export CPATH=${pkgs.zlib.dev}/include:$CPATH

            export PS1="\n\[\033[1;34m\][tmdb-fetcher:\w]\$\[\033[0m\] "

            echo "Haskell TMDB Fetcher Development Environment"
            echo "-------------------------------------------"
            echo "GHC: $(ghc --version)"
            echo "Cabal: $(cabal --version | head -n 1)"

            if [ -z "$TMDB_API_KEY" ]; then
              echo ""
              echo "⚠️  WARNING: TMDB_API_KEY environment variable is not set."
              echo "You'll need to set this before running the fetcher:"
              echo "export TMDB_API_KEY=your_api_key_here"
            else
              echo "TMDB API Key: ✓"
            fi

            echo ""
            echo "Available commands:"
            echo "  build          - Build the project"
            echo "  run            - Run the fetcher with the default output path"
            echo "  run-with-path  - Run with a custom output path (arg: path)"
            echo ""

            function build() {
              cabal build
            }

            function run() {
              mkdir -p ${defaultOutputPath}
              cabal run tmdb-fetcher -- ${defaultOutputPath}/movies.json
            }

            function run-with-path() {
              if [ -z "$1" ]; then
                echo "Error: Please specify an output path"
                echo "Usage: run-with-path /path/to/output/movies.json"
                return 1
              fi

              # Ensure directory exists
              mkdir -p "$(dirname "$1")"

              cabal run tmdb-fetcher -- "$1"
            }
          '';
        };
      }
    );
}
