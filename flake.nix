{
  description = "Orca Slicer with NVIDIA Wayland support";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Create a wrapper that detects NVIDIA and applies proper environment variables
        orca-slicer-nvidia-wayland = pkgs.writeShellScriptBin "orca-slicer" ''
          # Check if we're running on Wayland
          if [ -n "$WAYLAND_DISPLAY" ]; then
            echo "Detected Wayland session"

            # Check for NVIDIA GPU
            if command -v nvidia-smi &> /dev/null && nvidia-smi &> /dev/null; then
              echo "NVIDIA GPU detected, applying Wayland workarounds..."

              # Try hardware-accelerated approach first (Zink)
              if [ -f "/run/opengl-driver/lib/dri/zink_dri.so" ] || [ -f "/usr/lib/dri/zink_dri.so" ]; then
                echo "Using Zink for hardware acceleration"
                export __GLX_VENDOR_LIBRARY_NAME=mesa
                export __EGL_VENDOR_LIBRARY_FILENAMES=/run/opengl-driver/share/glvnd/egl_vendor.d/50_mesa.json
                export MESA_LOADER_DRIVER_OVERRIDE=zink
                export GALLIUM_DRIVER=zink
              else
                echo "Zink not available, falling back to software rendering"
                export __EGL_VENDOR_LIBRARY_FILENAMES=/run/opengl-driver/share/glvnd/egl_vendor.d/50_mesa.json
              fi

              # Disable DMA-BUF for WebKit (fixes preview pane)
              export WEBKIT_DISABLE_DMABUF_RENDERER=1

              # Additional NVIDIA Wayland environment variables
              export __GL_SYNC_TO_VBLANK=0
              export __GL_THREADED_OPTIMIZATIONS=1

            else
              echo "No NVIDIA GPU detected"
            fi
          else
            echo "Running on X11"
          fi

          # Launch Orca Slicer
          exec ${pkgs.orca-slicer}/bin/orca-slicer "$@"
        '';

        # Create desktop entry
        orca-slicer-desktop = pkgs.makeDesktopItem {
          name = "orca-slicer-nvidia-wayland";
          desktopName = "Orca Slicer (NVIDIA Wayland)";
          exec = "${orca-slicer-nvidia-wayland}/bin/orca-slicer %F";
          icon = "orca-slicer";
          comment = "3D Slicer for FDM/FFF 3D Printers with NVIDIA Wayland support";
          categories = [
            "Graphics"
            "3DGraphics"
            "Engineering"
          ];
          mimeTypes = [
            "model/stl"
            "application/vnd.ms-3mfdocument"
            "application/prs.wavefront-obj"
            "application/x-amf"
            "x-scheme-handler/orcaslicer"
          ];
          startupNotify = true;
        };

        # Full package with all dependencies
        orca-slicer-full = pkgs.buildEnv {
          name = "orca-slicer-nvidia-wayland";
          paths = [
            orca-slicer-nvidia-wayland
            orca-slicer-desktop
            pkgs.orca-slicer

            # Required for NVIDIA Wayland support
            pkgs.mesa
            pkgs.libglvnd
            pkgs.vulkan-loader
            pkgs.vulkan-tools

            # Additional dependencies that might be needed
            pkgs.libGL
            pkgs.libGLU
            pkgs.freeglut
            pkgs.glib
            pkgs.gtk3
            pkgs.webkitgtk
            pkgs.cairo
            pkgs.pango
            pkgs.harfbuzz
            pkgs.gdk-pixbuf
            pkgs.atk
          ];

          # Make sure desktop file is installed
          postBuild = ''
            mkdir -p $out/share/applications
            cp ${orca-slicer-desktop}/share/applications/* $out/share/applications/

            # Copy icon if available
            if [ -d "${pkgs.orca-slicer}/share/icons" ]; then
              mkdir -p $out/share/icons
              cp -r ${pkgs.orca-slicer}/share/icons/* $out/share/icons/
            fi
          '';
        };

      in
      {
        packages = {
          default = orca-slicer-full;
          orca-slicer = orca-slicer-full;
          orca-slicer-wrapper = orca-slicer-nvidia-wayland;
        };

        apps = {
          default = {
            type = "app";
            program = "${orca-slicer-nvidia-wayland}/bin/orca-slicer";
          };
          orca-slicer = {
            type = "app";
            program = "${orca-slicer-nvidia-wayland}/bin/orca-slicer";
          };
        };

        # Development shell for testing
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            orca-slicer-full

            # Development tools
            vulkan-tools
            glxinfo
            nvidia-gpu-info
            pciutils

            # Debugging tools
            strace
            ltrace
            gdb
          ];

          shellHook = ''
            echo "Orca Slicer NVIDIA Wayland Development Shell"
            echo "========================================"
            echo ""
            echo "Available commands:"
            echo "  orca-slicer       - Launch Orca Slicer with NVIDIA Wayland support"
            echo "  vulkaninfo        - Show Vulkan info"
            echo "  glxinfo           - Show OpenGL info"
            echo "  nvidia-smi        - Show NVIDIA GPU info (if available)"
            echo ""
            echo "Environment variables that will be set automatically:"
            echo "  - WAYLAND_DISPLAY detection"
            echo "  - NVIDIA GPU detection"
            echo "  - Zink driver configuration"
            echo "  - WebKit DMA-BUF workarounds"
            echo ""

            # Show current environment info
            if [ -n "$WAYLAND_DISPLAY" ]; then
              echo "Current session: Wayland"
            else
              echo "Current session: X11"
            fi

            if command -v nvidia-smi &> /dev/null; then
              echo "NVIDIA GPU: Available"
            else
              echo "NVIDIA GPU: Not detected"
            fi

            if [ -f "/run/opengl-driver/lib/dri/zink_dri.so" ]; then
              echo "Zink driver: Available"
            else
              echo "Zink driver: Not found"
            fi
          '';
        };
      }
    );
}
