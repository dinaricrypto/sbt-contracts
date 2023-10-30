#!/bin/sh

# Fetch secrets from aws
SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id <SecretID> --query <SecretString> --output text)
# Set secrets as environment variables
SENDER_KEY=$(echo $SECRET_JSON | jq -r .SENDER_KEY)

forge script script/TransferAll.s.sol:TransferAllScript --rpc-url $RPC_ARBITRUM --broadcast -vvvv
# cast send --rpc-url $RPC_ARBITRUM --private-key $SENDER_KEY --value $SEND_AMOUNT $TO
