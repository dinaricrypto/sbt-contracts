#!/bin/sh

source .env

forge snapshot -f $RPC_ARBITRUM --match-path test/forwarder/**/\* > .gas-snapshot-fork