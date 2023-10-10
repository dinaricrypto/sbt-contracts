#!/bin/sh

source .env

forge test -f $RPC_ARBITRUM --gas-report --fuzz-seed 1 | grep '^|' > .gas-report
