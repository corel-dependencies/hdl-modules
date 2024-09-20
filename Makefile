SHELL := /bin/bash
.PHONY: help install develop uninstall clean

# https://gist.github.com/prwhite/8168133?permalink_comment_id=3624253#gistcomment-3624253
help: ## Show the help message.
	@awk 'BEGIN {FS = ":.*##"; printf "make options: \033[36m\033[0m\n"} /^[$$()% a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

install: ## Install the package.
	pip install .

develop: ## Install the package in development/editable mode.
	pip install -e .

uninstall: ## Uninstall the package.
	@rm -rf hdl_modules.egg-info  # Fix for strange behaviour on macos + conda + in-tree-build
	@rm -rf build
	pip uninstall -y hdl-modules

clean: uninstall ## Clean generated files and uninstall the package.
