#!/bin/sh

cp .env-kinto-prod .env
source .env

forge script script/kinto/DeployAllCreate2.s.sol:DeployAllCreate2 --rpc-url $RPC_URL -vvvv --broadcast --skip-simulation
# forge verify-contract --watch 0xa669d3603C83BAfB4bD38DA9E3847ecCdA75dC65 src/UsdPlusRedeemer.sol:UsdPlusRedeemer --verifier blockscout --verifier-url https://explorer.kinto.xyz/api --chain-id 7887
