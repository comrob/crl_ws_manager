SHELL := /usr/bin/env bash

TOOLS_DIR   := $(HOME)/.local/bin
CONFIG_DIR  := $(HOME)/.config/crl_ws_manager
BASHRC      := $(HOME)/.bashrc

COMMANDS    := ws ws-build ws-clean ws-cd-resolve ws-list ws-open ws-config ws-which

SOURCE_BEGIN := \# >>> crl ws manager source >>>
SOURCE_END   := \# <<< crl ws manager source <<<

.PHONY: install uninstall purge

install:
	@bash install.sh

uninstall:
	@echo "Removing symlinks from $(TOOLS_DIR) ..."
	@for cmd in $(COMMANDS) ws_lib.sh; do \
	  dest="$(TOOLS_DIR)/$$cmd"; \
	  if [[ -L "$$dest" ]]; then \
	    unlink "$$dest" && echo "  Removed $$dest"; \
	  elif [[ -f "$$dest" ]]; then \
	    echo "  [SKIP] $$dest is a regular file — remove manually"; \
	  fi; \
	done
	@echo "Removing shell functions file ..."
	@dest="$(CONFIG_DIR)/ws_manager.bash"; \
	if [[ -L "$$dest" ]]; then \
	  unlink "$$dest" && echo "  Removed $$dest"; \
	elif [[ -f "$$dest" ]]; then \
	  echo "  [SKIP] $$dest is a regular file — remove manually"; \
	fi
	@dest="$(CONFIG_DIR)/ws_lib.sh"; \
	if [[ -L "$$dest" ]]; then \
	  unlink "$$dest" && echo "  Removed $$dest"; \
	fi
	@echo "Removing source block from $(BASHRC) ..."
	@if grep -qF '$(SOURCE_BEGIN)' "$(BASHRC)" 2>/dev/null; then \
	  tmp=$$(mktemp); \
	  awk \
	    -v begin='# >>> crl ws manager source >>>' \
	    -v end='# <<< crl ws manager source <<<' \
	    'BEGIN{skip=0} $$0==begin{skip=1;next} $$0==end{skip=0;next} skip==0{print}' \
	    "$(BASHRC)" > "$$tmp" && mv "$$tmp" "$(BASHRC)" && \
	  echo "  Removed source block from $(BASHRC)"; \
	else \
	  echo "  Source block not found in $(BASHRC), nothing to remove"; \
	fi
	@echo "Done. Run 'source $(BASHRC)' or open a new terminal to apply."

# purge: uninstall + remove the local config file and config directory.
# The config file (~/.config/crl_ws_manager/ws_config.bash) contains user
# customisations; this target will prompt before deleting it.
purge: uninstall
	@cfg="$(CONFIG_DIR)/ws_config.bash"; \
	if [[ -f "$$cfg" ]]; then \
	  read -r -p "  Delete local config $$cfg? [y/N] " ans; \
	  if [[ "$$ans" =~ ^[Yy]$$ ]]; then \
	    rm -f "$$cfg" && echo "  Removed $$cfg"; \
	  else \
	    echo "  Kept $$cfg"; \
	  fi; \
	fi
	@if [[ -d "$(CONFIG_DIR)" ]] && [[ -z "$$(ls -A "$(CONFIG_DIR)" 2>/dev/null)" ]]; then \
	  rmdir "$(CONFIG_DIR)" && echo "  Removed empty directory $(CONFIG_DIR)"; \
	fi
