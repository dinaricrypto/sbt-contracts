#!/bin/sh

op run --env-file="./.env.staging-sepolia" -- ./script/deploypricehelper-cmd.sh

op run --env-file="./.env.staging-arb-sepolia" -- ./script/deploypricehelper-cmd.sh

# no-op: use staging-sepolia
# op run --env-file="./.env.sandbox" -- ./script/deploypricehelper-cmd.sh

op run --env-file="./.env.prod-base" -- ./script/deploypricehelper-cmd.sh

op run --env-file="./.env.prod-eth" -- ./script/deploypricehelper-cmd.sh

op run --env-file="./.env.prod-kinto" -- ./script/kinto/deploypricehelper-cmd.sh

op run --env-file="./.env.prod-arb" -- ./script/deploypricehelper-cmd.sh
