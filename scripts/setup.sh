#!/bin/bash
# IRIS — setup script pour nouvelle machine Mac.
# Installe Tuist + Xcode CLT si manquants. Run : `./scripts/setup.sh`

set -euo pipefail

bold() { printf "\033[1m%s\033[0m\n" "$1"; }

bold "▶ IRIS setup"

# 1. Vérifier macOS
if [ "$(uname)" != "Darwin" ]; then
  echo "❌ Ce setup est macOS-only (IRIS = Mac native SwiftUI)."
  exit 1
fi

# 2. Vérifier / installer Xcode CLT
if ! xcode-select -p &>/dev/null; then
  bold "▶ Installation Xcode Command Line Tools"
  xcode-select --install
  echo "⚠️  Lance le wizard Xcode CLT puis re-run ce script."
  exit 0
else
  echo "✓ Xcode CLT installé : $(xcode-select -p)"
fi

# 3. Vérifier Xcode app
if ! command -v xcodebuild &>/dev/null; then
  echo "❌ Xcode app introuvable. Installe-le depuis l'App Store, puis re-run."
  exit 1
fi
echo "✓ Xcode : $(xcodebuild -version | head -1)"

# 4. Vérifier Swift 6+
SWIFT_VERSION=$(swift --version 2>/dev/null | grep -oE 'Swift version [0-9]+\.[0-9]+' | head -1 | awk '{print $3}')
if [ -z "${SWIFT_VERSION}" ]; then
  echo "❌ Swift introuvable."
  exit 1
fi
echo "✓ Swift : ${SWIFT_VERSION}"

# 5. Homebrew
if ! command -v brew &>/dev/null; then
  bold "▶ Installation Homebrew"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
echo "✓ Homebrew : $(brew --version | head -1)"

# 6. Tuist
if ! command -v tuist &>/dev/null; then
  bold "▶ Installation Tuist"
  brew install tuist
fi
echo "✓ Tuist : $(tuist version)"

# 7. Generate + build
bold "▶ Tuist install + generate"
tuist install
tuist generate --no-open

bold "▶ Build verify"
xcodebuild -workspace IRIS.xcworkspace -scheme IRIS -destination 'platform=macOS' -configuration Debug build | tail -3

bold "✅ Setup OK. Lance : make run"
