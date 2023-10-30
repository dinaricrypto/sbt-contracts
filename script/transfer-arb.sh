#!/bin/sh

# Fetch secrets from aws
SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id <SecretID> --query <SecretString> --output text)
# Set secrets as environment variables
SENDER_KEY=$(echo $SECRET_JSON | jq -r .SENDER_KEY)

forge script script/Transfer.s.sol:TransferScript --rpc-url $RPC_ARBITRUM --broadcast -vvvv
