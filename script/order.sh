#!/bin/sh

op run --env-file="./.env.prod-plume" -- ./script/order-cmd.sh
