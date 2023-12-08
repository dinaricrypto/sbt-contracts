#!/bin/sh

cp .env.prod .env
source .env

forge test -f $RPC_URL --gas-report --fuzz-seed 1 | grep '^|' > .gas-report
