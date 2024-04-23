#!/bin/sh

cp .env.arb-sepolia .env
source .env

forge create --rpc-url $RPC_URL --private-key $DEPLOY_KEY OrderProcessor
