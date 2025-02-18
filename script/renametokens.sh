#!/bin/sh

# op run --env-file="./.env.prod-arb" -- ./script/renametokens-cmd.sh

# op run --env-file="./.env.prod-eth" -- ./script/renametokens-cmd.sh

# op run --env-file="./.env.prod-base" -- ./script/renametokens-cmd.sh

# op run --env-file="./.env.prod-blast" -- ./script/renametokens-cmd.sh

# op run --env-file="./.env.prod-plume" -- ./script/renametokens-cmd.sh

op run --env-file="./.env.prod-kinto" -- ./script/renametokens-cmd.sh

# op run --env-file="./.env.sandbox" -- ./script/renametokens-cmd.sh
