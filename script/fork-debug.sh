#!/bin/sh

cp .env.eth-sepolia .env
source .env

forge debug --match-path test/fork/* --fork-url $RPC_URL
