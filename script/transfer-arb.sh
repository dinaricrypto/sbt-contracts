#!/bin/sh

cp .env.prod-arb .env
source .env

cast send --rpc-url $RPC_URL --private-key $DEPLOYER_KEY 0xAdFeB630a6aaFf7161E200088B02Cf41112f8B98 --value 0.4ether
