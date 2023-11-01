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
SENDER_KEY=$(echo $SECRET_JSON | jq -r .SENDER_KEY)

forge script script/TransferAll.s.sol:TransferAllScript --rpc-url $RPC_ARBITRUM --broadcast -vvvv
# cast send --rpc-url $RPC_ARBITRUM --private-key $SENDER_KEY --value $SEND_AMOUNT $TO
