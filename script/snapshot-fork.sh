#!/bin/sh

source .env

forge snapshot -f $RPC_URL --match-path test/forwarder/**/\* > .gas-snapshot-fork