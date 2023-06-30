#!/bin/sh

source .env

forge script script/UpgradeIssuer.s.sol:UpgradeIssuerScript --rpc-url $ARB_URL --etherscan-api-key $ARBISCAN_API_KEY --broadcast --verify -vvvv
