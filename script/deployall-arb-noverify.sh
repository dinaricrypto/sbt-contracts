#!/bin/sh

source .env

forge script script/DeployAll.s.sol:DeployAllScript --rpc-url $RPC_URL --broadcast -vvvv
