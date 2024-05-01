#!/bin/sh

cp .env.eth-sepolia .env
source .env

forge test --match-path test/fork/* --fork-url $RPC_URL -vvv
