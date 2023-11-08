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
PRIVATE_KEY=$(echo $SECRET_JSON | jq -r .PRIVATE_KEY)

forge script script/PauseProcessors.s.sol:PauseProcessorsScript --rpc-url $RPC_URL --broadcast -vvvv
