#!/bin/sh

source .env

forge verify-contract --chain-id 42161 --etherscan-api-key $ARBISCAN_API_KEY --watch --constructor-args $(cast abi-encode "constructor(address,string,string,string,address)" "0x269e944aD9140fc6e21794e8eA71cE1AfBfe38c8" "Meta Platforms - Dinari" "META.D" "" "0xec3b79d771b47a0f5db925d7faf793605f5560ce") 0xa40c0975607BDbF7B868755E352570454b5B2e48 src/dShare.sol:dShare
