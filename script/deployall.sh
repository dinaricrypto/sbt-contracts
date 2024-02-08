#!/bin/sh

cp .env.prod-eth .env
source .env

forge script script/DeployAll.s.sol:DeployAll --rpc-url $RPC_URL -vvv --broadcast --verify
```
