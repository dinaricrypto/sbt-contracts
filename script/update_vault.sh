#!/bin/bash
# Executes the UpdateVaultForOrderProcessor script on the specified RPC URL
#
# Required environment variables:
# ENVIRONMENT           - Target environment ["staging", "production"]
# RPC_URL              - RPC endpoint URL
# CHAIN_ID             - Chain ID of RPC
# PRIVATE_KEY          - Deploy private key
# ORDER_PROCESSOR_ADDRESS - Address of the deployed OrderProcessor contract

echo "========================"
echo "UpdateVaultForOrderProcessor: Executing"

# Base Forge command
FORGE_CMD="forge script script/UpdateVaultForOrderProcessor.s.sol -vvv --rpc-url $RPC_URL --private-key $PRIVATE_KEY --slow"

# Append chain-specific modifications
if [ "$CHAIN_ID" == "98864" ] || [ "$CHAIN_ID" == "98865" ]; then
  FORGE_CMD="$FORGE_CMD --legacy --skip-simulation"
elif [ "$CHAIN_ID" == "7887" ]; then
  FORGE_CMD="$FORGE_CMD --skip-simulation"
fi

# Execute the command with the environment variable set
FOUNDRY_DISABLE_NIGHTLY_WARNING=True $FORGE_CMD

echo "========================"