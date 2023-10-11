#!/bin/sh

forge test --match-path test/main/**/\* --gas-report --fuzz-seed 1 | grep '^|' > .gas-report
