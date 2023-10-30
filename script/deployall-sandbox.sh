#!/bin/sh

# Fetch secrets from aws
SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id <SecretID> --query <SecretString> --output text)
# Set secrets as environment variables
S_DEPLOY_KEY=$(echo $SECRET_JSON | jq -r .S_DEPLOY_KEY)

forge script script/DeployAllSandbox.s.sol:DeployAllSandboxScript --rpc-url $TEST_RPC_URL --broadcast --verify -vvvv
