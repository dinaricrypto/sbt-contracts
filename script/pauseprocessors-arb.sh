#!/bin/sh

# Fetch secrets from aws
SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id <SecretID> --query <SecretString> --output text)
# Set secrets as environment variables
PRIVATE_KEY=$(echo $SECRET_JSON | jq -r .PRIVATE_KEY)

forge script script/PauseProcessors.s.sol:PauseProcessorsScript --rpc-url $RPC_ARBITRUM --broadcast -vvvv
