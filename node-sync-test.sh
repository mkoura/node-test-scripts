#!/usr/bin/env nix-shell
#!nix-shell -i bash -p yj


###############################
# THIS SCRIPT IS OBSOLETE NOW #
#      	   MAY 2020           #
#                             #
###############################


set -euo pipefail

git clone git@github.com:input-output-hk/cardano-node.git
cd cardano-node
git checkout ${GIT_REV:-master}
cd benchmarking/chain-sync

BASEDIR="$(dirname $0)"

# cpu time limit in minutes with default value - 5 minutes
TIME_LIMIT=$((${MINUTES:-5}*60))

CLUSTER="${NETWORK:-testnet}"

LOG_CONFIG="$(yj < $BASEDIR/configuration/log-config-ci.yaml)"

CUSTOM_CONFIG="{nodeConfig = builtins.fromJSON ''$LOG_CONFIG'';}"

nix build --out-link ./launch_node -f $BASEDIR/../.. scripts.$CLUSTER.node --arg customConfig "$CUSTOM_CONFIG"

rm -rf "./state-node-$CLUSTER"

timeout ${TIME_LIMIT} ./launch_node || true

$BASEDIR/analyse-logs.sh ${CLUSTER} | tee ../../../results.log
