#!/bin/sh

source .env

forge coverage -f $RPC_URL --report lcov && genhtml --branch-coverage --dark-mode -o ./coverage/ lcov.info
