#!/bin/sh

cp .env.prod-kinto .env
source .env

forge script script/ConfigOperators.s.sol:ConfigOperators --rpc-url $RPC_URL --broadcast -vvv --skip-simulation --slow
