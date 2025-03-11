#!/bin/bash
# Grants roles to accounts for specified contracts on a target network
#
# Required environment variables:
# VERSION            - Version of the deployed contracts
# ENVIRONMENT        - Target environment ["staging", "production"]
# RPC_URL            - RPC endpoint URL
# CHAIN_ID           - Chain Id of RPC
# PRIVATE_KEY        - Private key for broadcasting transactions

# Define contracts that need role assignments
CONTRACTS=("TransferRestrictor" "Vault" "FulfillmentRouter" "OrderProcessor")

echo "Starting role assignment process for $ENVIRONMENT environment, version $VERSION"

for i in "${CONTRACTS[@]}"; do
  echo "========================"
  echo "$i: Assigning roles"

  # Base Forge command for the Onoff script
  FORGE_CMD="CONTRACT_NAME=$i VERSION=$VERSION ENVIRONMENT=$ENVIRONMENT FOUNDRY_DISABLE_NIGHTLY_WARNING=True forge script script/Onoff.s.sol:Onoff -vvv --rpc-url $RPC_URL --private-key $PRIVATE_KEY"

  # Execute the command
  eval $FORGE_CMD
  if [ $? -eq 0 ]; then
    echo "$i: Roles assigned successfully"
  else
    echo "$i: Failed to assign roles"
  fi
  echo "========================"
done

echo "Role assignment process completed"