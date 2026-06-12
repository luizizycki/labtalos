#!/usr/bin/env bash
set -euo pipefail

# Check for required commands
REQUIRED_COMMANDS=("terraform" "kubectl" "helm")
MISSING=0

echo "Checking dependencies for labtalos..."

for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "❌ [MISSING] $cmd is not installed or not in PATH."
        MISSING=1
    else
        echo "✅ [FOUND] $cmd ($(which "$cmd"))"
    fi
done

# Check for optional but recommended commands
OPTIONAL_COMMANDS=("talosctl")
for cmd in "${OPTIONAL_COMMANDS[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "ℹ️  [OPTIONAL] $cmd is not installed. You may want to install it to interact with Talos nodes."
    else
        echo "✅ [FOUND] $cmd ($(which "$cmd"))"
    fi
done

if [ "$MISSING" -ne 0 ]; then
    echo "Error: Missing required dependencies. Please install them before proceeding."
    exit 1
else
    echo "All required dependencies are installed! Ready to deploy."
fi
