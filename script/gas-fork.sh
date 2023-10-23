#!/bin/sh

source .env

forge test -f $RPC_ARBITRUM --match-path test/forwarder/**/\* --gas-report --fuzz-seed 1 | grep '^|' > .gas-report-fork