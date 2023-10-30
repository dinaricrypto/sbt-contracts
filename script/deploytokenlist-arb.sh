#!/bin/sh

# Fetch secrets from aws
SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id <SecretID> --query <SecretString> --output text)
# Set secrets as environment variables
DEPLOY_KEY=$(echo $SECRET_JSON | jq -r .DEPLOY_KEY)

forge script script/DeployTokenList.s.sol:DeployTokenListScript --rpc-url $RPC_ARBITRUM --etherscan-api-key $ARBISCAN_API_KEY --broadcast -vvvv
