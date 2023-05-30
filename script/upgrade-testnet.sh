#!/bin/sh

source .env

forge script script/UpgradeIssuer.s.sol:UpgradeIssuerScript --rpc-url $TEST_RPC_URL --broadcast --verify -vvvv
