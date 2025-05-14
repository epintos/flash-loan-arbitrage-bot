#!/bin/bash

# Script to build Forge contracts and copy ABI files

echo "📝 Updating FlashLoanArbitrage ABI..."

# Step 1: Navigate to smart-contracts directory
echo "👉 Changing to ../smart-contracts directory..."
cd ../smart-contracts || {
  echo "❌ Error: ../smart-contracts directory not found"
  exit 1
}

# Step 2: Run make build
echo "🔨 Running forge build..."
make build || {
  echo "❌ Error: forge build failed"
  exit 1
}

# Step 3: Copy ABI from out directory to abis folder
echo "📋 Copying ABI file..."

ABI_FILE=$(find out -name "FlashLoanArbitrage.json" | grep -v "metadata")
if [ -z "$ABI_FILE" ]; then
  # Try alternative path pattern if not found
  ABI_FILE=$(find out -path "*/FlashLoanArbitrage.sol/FlashLoanArbitrage.json")
fi

if [ -z "$ABI_FILE" ]; then
  echo "❌ Error: Could not find FlashLoanArbitrage.json ABI file"
  exit 1
fi

# Navigate back to the original directory
cd - || exit 1

# Create abis directory if it doesn't exist
mkdir -p abis

# Copy the ABI file
cp "../smart-contracts/$ABI_FILE" abis/FlashLoanArbitrage.json

# Extract just the ABI array from the Forge output if necessary
if [ -f "abis/FlashLoanArbitrage.json" ]; then
  echo "📄 Extracting ABI array from Forge output..."
  # Use jq to extract just the abi array if jq is available
  if command -v jq &> /dev/null; then
    jq '.abi' abis/FlashLoanArbitrage.json > abis/FlashLoanArbitrage.tmp.json && mv abis/FlashLoanArbitrage.tmp.json abis/FlashLoanArbitrage.json
  else
    echo "⚠️ Warning: jq not found. The ABI file might contain extra Forge output data."
    echo "⚠️ Consider installing jq for proper ABI extraction: npm install -g node-jq"
  fi
fi

echo "✅ ABI update completed successfully!"
echo "📍 ABI file is now at: abis/FlashLoanArbitrage.json"
