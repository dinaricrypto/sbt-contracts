#!/bin/sh

# Source the .env file
source .env
# Fetch secrets from aws
SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id $MAINNET_SECRET_ID --query SecretString --output text)
if [ $? -ne 0 ]; then
    echo "Error: Failed to fetch secret from AWS Secrets Manager"
    exit 2
fi
# Set secrets as environment variables
DEPLOY_KEY=$(echo $SECRET_JSON | jq -r .DEPLOY_KEY)

# Use secrets in your deployment script
forge script script/DeployAll.s.sol:DeployAllScript --rpc-url $RPC_ARBITRUM --etherscan-api-key $ARBISCAN_API_KEY --broadcast --verify -vvvv
