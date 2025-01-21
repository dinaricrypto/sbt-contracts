#!/bin/sh

op run --env-file="./.env.prod-plume" -- ./script/nest/setstalepriceduration-cmd.sh
