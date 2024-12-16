#!/bin/sh

op run --env-file="./.env.prod-kinto" -- ./script/kinto/addtoappwhitelist-cmd.sh
