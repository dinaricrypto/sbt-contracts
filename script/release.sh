#!/bin/bash
# Releases set of contracts to specified RPC url
#
# Required environment variables:
# VERSION            - Version of deployment
# ENVIRONMENT        - Target environment ["staging", "production"]
# RPC_URL            - RPC endpoint URL
# CHAIN_ID           - Chain Id of RPC
# PRIVATE_KEY        - Deploy private key
#
# Optional:
# VERIFY_URL         - Contract verifier URL (if not using Etherscan)
# ETHERSCAN_API_KEY  - Etherscan API key
# DEPLOYED_VERSION   - Version of the previous deployment

CONTRACTS=("TransferRestrictor" "DividendDistribution" "FulfillmentRouter" "Vault" "DShare" "WrappedDShare" "DShareFactory" "OrderProcessor")

for i in "${CONTRACTS[@]}"; do
  echo "========================"
  echo "$i: Releasing"

  FORGE_CMD="CONTRACT=$i FOUNDRY_DISABLE_NIGHTLY_WARNING=True forge script script/Release.s.sol -vvv --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast --slow"

  # Append chain-specific modifications
  if [ "$CHAIN_ID" == "98867" ]; then
    FORGE_CMD="$FORGE_CMD --legacy --skip-simulation"
  elif [ "$CHAIN_ID" == "7887" ]; then
    FORGE_CMD="$FORGE_CMD --skip-simulation"
  fi

  # Append verifier commands if available
  if [ ! -z "$ETHERSCAN_API_KEY" ] || [ ! -z "$VERIFIER_URL" ]; then
    FORGE_CMD="$FORGE_CMD --verify --delay 10 --retries 30"

    # Append chain-specific modifications
    if [ "$CHAIN_ID" == "98866" ] || [ "$CHAIN_ID" == "98867" ] || [ "$CHAIN_ID" == "7887" ]; then
      FORGE_CMD="$FORGE_CMD --verifier blockscout"
    fi
  fi

  eval $FORGE_CMD || rm -f artifacts/${ENVIRONMENT}/${CHAIN_ID}.${i}.json
  echo "========================"
done