#!/bin/bash
# Executes the Restrict script on the specified RPC URL
#
# Required environment variables:
# ENVIRONMENT        - Target environment ["production"]
# RPC_URL           - RPC endpoint URL
# CHAIN_ID          - Chain ID of RPC
# PRIVATE_KEY       - Deploy private key

echo "========================"
echo "Restrict addresses: Executing"

# Base Forge command without the environment variable inline
FORGE_CMD="forge script script/Restrict.s.sol -vvv --rpc-url $RPC_URL --private-key $PRIVATE_KEY  --broadcast --slow"

# Append chain-specific modifications
if [ "$CHAIN_ID" == "98864" ] || [ "$CHAIN_ID" == "98865" ]; then
  FORGE_CMD="$FORGE_CMD --legacy --skip-simulation"
elif [ "$CHAIN_ID" == "7887" ]; then
  FORGE_CMD="$FORGE_CMD --skip-simulation"
fi

# Execute the command with the environment variable set
FOUNDRY_DISABLE_NIGHTLY_WARNING=True $FORGE_CMD

echo "========================"