#!/bin/sh

source .env

forge script script/DeployForwarder.s.sol:DeployForwarderScript --rpc-url $RPC_URL --broadcast --verify -vvvv
