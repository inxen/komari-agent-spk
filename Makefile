# Makefile for the Komari Agent Synology SPK packaging project.
#
# Targets:
#   make download   - download official agent binaries + verify SHA256
#   make build      - alias for download (there is nothing to compile)
#   make package    - build the .spk natively via the Synology Toolkit
#   make test       - run static + packaging checks (no DSM required)
#   make all        - download -> verify -> build SPK -> check -> dist/*.spk
#   make clean      - remove build artifacts
#
# Building the .spk uses the official Synology pkgscripts-ng Toolkit natively
# (root + chroot). See tools/build_spk_native.sh for details.

SHELL := /bin/bash

# ---- Config -----------------------------------------------------------------
VERSION_FILE := VERSION
UPSTREAM_VERSION := $(shell head -n1 $(VERSION_FILE) | tr -d '[:space:]' | cut -d'-' -f1)
SPK_VERSION := $(shell head -n1 $(VERSION_FILE) | tr -d '[:space:]')

# Upstream binary asset suffixes (used by download).
DOWNLOAD_ARCHS := amd64 arm64 arm
# Synology architecture families (used by the SPK build).
SPK_ARCHS := x86_64 armv7 armv8

DIST_DIR := dist
DOWNLOAD_DIR := downloads

# -----------------------------------------------------------------------------
.PHONY: all download build package test clean toolkit-clean distclean help

help:
	@echo "Komari Agent Synology SPK builder"
	@echo "  make download   - download official binaries + SHA256 verify"
	@echo "  make build      - alias for download (nothing to compile)"
	@echo "  make package    - build the .spk natively (Synology Toolkit, needs sudo)"
	@echo "  make test       - run static checks (no DSM required)"
	@echo "  make all        - download -> package -> test -> dist/*.spk"
	@echo "  make clean      - remove build artifacts"

# ---- Download + verify ------------------------------------------------------
download:
	@echo "==> Downloading komari-agent v$(UPSTREAM_VERSION) binaries"
	@for arch in $(DOWNLOAD_ARCHS); do \
		./tools/download-agent.sh $(UPSTREAM_VERSION) $$arch; \
	done

build: download

# ---- Build the SPK natively via the Synology Toolkit -----------------------
# Uses the official pkgscripts-ng Toolkit in a chroot (needs root). Each arch
# chroot is ~6-7GB and is removed after building to keep disk usage low.
TOOLKIT_DIR ?= /toolkit
TARBALL_DIR ?= $(TOOLKIT_DIR)/toolkit_tarballs

package: download
	@echo "==> Building SPK natively (Synology Toolkit, requires sudo)"
	@if [ ! -d "$(TOOLKIT_DIR)/pkgscripts-ng" ]; then \
		echo "Cloning Synology pkgscripts-ng (DSM7.4) into $(TOOLKIT_DIR) ..."; \
		sudo mkdir -p "$(TOOLKIT_DIR)"; \
		sudo git clone --depth 1 -b DSM7.4 \
			https://github.com/SynologyOpenSource/pkgscripts-ng.git "$(TOOLKIT_DIR)/pkgscripts-ng"; \
	fi
	sudo bash tools/build_spk_native.sh $(SPK_ARCHS)
	@echo "==> SPK built. Artifacts in $(DIST_DIR)/"

# ---- Static checks (no DSM required) ----------------------------------------
test:
	@bash tests/check_static.sh

# ---- All ---------------------------------------------------------------------
all: package test
	@echo "==> Done. SPK files:"
	@ls -l $(DIST_DIR)/*.spk 2>/dev/null || echo "  (no spk produced)"

# ---- Cleanup -----------------------------------------------------------------
clean:
	rm -rf $(DIST_DIR) pkg_work INFO
	@echo "Cleaned build artifacts."

# Remove the cached Synology build environments too (forces full re-download).
toolkit-clean:
	sudo rm -rf $(TOOLKIT_DIR)/build_env
	@echo "Cleaned Toolkit build environments (re-downloaded on next build)."

distclean: clean toolkit-clean
	rm -rf $(DOWNLOAD_DIR)
	@echo "Cleaned download cache too."
