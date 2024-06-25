#!/bin/sh

cp .env.kinto-prod .env
source .env

forge script script/kinto/DeployAllCreate2.s.sol:DeployAllCreate2 --rpc-url $RPC_URL -vvvv --broadcast --skip-simulation --slow
# forge verify-contract --watch 0x57BF8A8b4CCE01AC91EECda5DD0828089d450eDC src/orders/OrderProcessor.sol:OrderProcessor --verifier blockscout --verifier-url https://explorer.kinto.xyz/api --chain-id 7887
