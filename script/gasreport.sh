#!/bin/sh

cp .env.prod-arb .env
source .env

forge test -f $RPC_URL --gas-report --fuzz-seed 1 | grep '^|' > .gas-report
