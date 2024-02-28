#!/bin/sh

source .env

forge snapshot -f $RPC_URL --match-path test/fork/**/\* > .gas-snapshot-fork