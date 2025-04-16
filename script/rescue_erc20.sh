#!/bin/bash
# Executes the Rescue script for specified chain IDs
#
# Required environment variables:
# ENVIRONMENT        - Target environment ["production"]
# RPC_URL           - RPC endpoint URL
# PRIVATE_KEY       - Deploy private key
#
# The script runs for chain IDs: <to be provided>

echo "========================"
echo "Move token from old vault to new vault: Starting"

# Check required environment variables
if [ -z "$ENVIRONMENT" ] || [ -z "$RPC_URL" ] || [ -z "$PRIVATE_KEY" ]; then
  echo "Error: ENVIRONMENT, RPC_URL, and PRIVATE_KEY must be set"
  exit 1
fi

# Define chain IDs (placeholder, to be updated by user)
CHAIN_IDS=("1" "7887" "8453" "42161" "98865")

# Iterate over chain IDs
for CHAIN_ID in "${CHAIN_IDS[@]}"; do
  echo "========================"
  echo "Chain $CHAIN_ID: Updating Operator"

  # Base Forge command
  FORGE_CMD="forge script script/RescueERC20.s.sol -vvv --rpc-url $RPC_URL --private-key $PRIVATE_KEY --slow"

  # Append chain-specific modifications
  if [ "$CHAIN_ID" == "98864" ] || [ "$CHAIN_ID" == "98865" ]; then
    FORGE_CMD="$FORGE_CMD --legacy --skip-simulation"
  elif [ "$CHAIN_ID" == "7887" ]; then
    FORGE_CMD="$FORGE_CMD --skip-simulation"
  fi

  # Execute the command
  FOUNDRY_DISABLE_NIGHTLY_WARNING=True $FORGE_CMD

  echo "========================"
done

echo "Rescue tokens: Completed"
echo "========================"