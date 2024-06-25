#!/bin/sh

cp .env.kinto-stage .env
source .env

forge script script/kinto/DeployAllCreate2.s.sol:DeployAllCreate2 --rpc-url $RPC_URL -vvvv --broadcast --skip-simulation --slow
# forge verify-contract --watch 0x251b1B7c4957FB9Db75921E50F4cf2a5e284b224 lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy --verifier blockscout --verifier-url https://explorer.kinto.xyz/api --chain-id 7887
