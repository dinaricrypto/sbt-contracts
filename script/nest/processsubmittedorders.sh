#!/bin/sh

op run --env-file="./.env.staging-plume" -- ./script/nest/processsubmittedorders-cmd.sh
