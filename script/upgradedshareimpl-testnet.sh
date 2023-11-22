#!/bin/sh

cp .env.test .env
source .env

forge script script/UpgradedShareImpl.s.sol:UpgradedShareImpl --rpc-url $RPC_URL -vvvv
