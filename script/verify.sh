#!/bin/bash
# Deploys to multiple blockchains using release.sh
#
# Required environment variables:
# CHAIN_ID           - Chain Id of RPC
# CONTRACT           - Name of contract
# CONTRACT_ADDRESS   - Address of contract
# AWS_SECRET_ID      - ARN of AWS secret to use

# Generate FORGE_CMD
FORGE_CMD="FOUNDRY_DISABLE_NIGHTLY_WARNING=True forge verify-contract -vvv --skip-is-verified-check"

# Append chain-specific modifications
if [ "$CHAIN_ID" == "98864" ] || [ "$CHAIN_ID" == "98865" ] || [ "$CHAIN_ID" == "7887" ]; then
  FORGE_CMD="$FORGE_CMD --verifier blockscout"
fi

# Complete FORGE_CMD
FORGE_CMD="$FORGE_CMD ${CONTRACT_ADDRESS} src/${CONTRACT}.sol:${CONTRACT}"

# Retrieve secrets from AWS
CHAIN_SECRETS=$(aws secretsmanager get-secret-value --secret-id "${AWS_SECRET_ID}" --query SecretString --output text)

# Prepend FORGE_CMD with secrets
FORGE_CMD="VERIFIER_URL=$(echo "${CHAIN_SECRETS}" | jq --raw-output ".VERIFIER_URL_${CHAIN_ID} // empty") ETHERSCAN_API_KEY=$(echo "${CHAIN_SECRETS}" | jq --raw-output ".ETHERSCAN_API_KEY_${CHAIN_ID} // empty") $FORGE_CMD"

eval $FORGE_CMD
