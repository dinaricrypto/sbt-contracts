#!/bin/sh

forge script script/kinto/AddToAppWhitelist.s.sol:AddToAppWhitelist --rpc-url $RPC_URL -vvv --broadcast --slow --skip-simulation
