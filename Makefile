# IRIS — Makefile dev helpers
# Cible : Mac Apple Silicon, macOS 26, Xcode 26, Tuist 4, Swift 6.
# Usage : `make <cible>`. Sans argument : `make help`.

.PHONY: help install generate build test run open clean format reset all

# Couleurs (compatible terminal Mac)
BOLD := $(shell tput bold)
RESET := $(shell tput sgr0)

help: ## Liste les commandes disponibles
	@echo ""
	@echo "$(BOLD)IRIS — dev commands$(RESET)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(BOLD)%-12s$(RESET) %s\n", $$1, $$2}'
	@echo ""

install: ## Tuist install (résoud + télécharge les deps Swift)
	tuist install

generate: install ## Tuist generate (régénère .xcodeproj/.xcworkspace)
	tuist generate --no-open

build: generate ## Build Debug macOS
	xcodebuild -workspace IRIS.xcworkspace -scheme IRIS -destination 'platform=macOS' -configuration Debug build | tail -10

test: generate ## Build + run tests
	xcodebuild -workspace IRIS.xcworkspace -scheme IRIS -destination 'platform=macOS' -configuration Debug test | tail -30

run: build ## Build puis lance l'app (équivalent à `open -a IRIS` après build)
	open -a IRIS

open: ## Ouvre le workspace dans Xcode
	open IRIS.xcworkspace

clean: ## Clean DerivedData + Tuist cache + build artifacts
	rm -rf ~/Library/Developer/Xcode/DerivedData/IRIS-*
	rm -rf .build Tuist/.build Tuist/Dependencies Tuist/Stencils
	rm -rf IRIS.xcodeproj IRIS.xcworkspace
	@echo "Cleaned. Run 'make generate' to rebuild."

reset: clean install generate ## Clean total + regenerate from scratch

format: ## Format Swift via swift-format (si installé)
	@if command -v swift-format >/dev/null 2>&1; then \
		swift-format format --in-place --recursive App Tests Project.swift Tuist/ProjectDescriptionHelpers; \
		echo "Formatted."; \
	else \
		echo "swift-format not installed. Install: brew install swift-format"; \
	fi

all: clean install generate build test ## Full pipeline (clean + install + generate + build + test)
