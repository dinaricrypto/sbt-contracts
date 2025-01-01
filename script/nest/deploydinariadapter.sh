#!/bin/sh

# op run --env-file="./.env.staging-plume" -- ./script/nest/deploydinariadapter-cmd.sh

op run --env-file="./.env.prod-plume" -- ./script/nest/deploydinariadapter-cmd.sh
