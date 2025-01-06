#!/bin/sh

# op run --env-file="./.env.staging-plume" -- ./script/nest/upgradedinariadapter-cmd.sh

op run --env-file="./.env.prod-plume" -- ./script/nest/upgradedinariadapter-cmd.sh
