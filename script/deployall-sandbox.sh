#!/bin/sh

cp .env.sandbox .env
source .env

forge script script/DeployAllSandbox.s.sol:DeployAllSandboxScript --rpc-url $RPC_URL --broadcast --verify -vvvv
