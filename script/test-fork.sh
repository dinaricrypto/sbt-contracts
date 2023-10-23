#!/bin/sh

source .env

forge test -f $RPC_ARBITRUM --match-path test/forwarder/**/\* -vvv