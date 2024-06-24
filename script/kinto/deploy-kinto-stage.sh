#!/bin/sh

cp .env-kinto-stage .env
source .env

forge script script/kinto/DeployAllCreate2.s.sol:DeployAllCreate2 --rpc-url $RPC_URL -vvvv --broadcast --skip-simulation
# forge verify-contract --watch 0x8C41BA7722e63a76EeC8a45f1005F057ff414fc1 src/UsdPlusRedeemer.sol:UsdPlusRedeemer --verifier blockscout --verifier-url https://explorer.kinto.xyz/api --chain-id 7887
