#!/usr/bin/env nix-shell
#!nix-shell -i bash -p yj

set -euo pipefail

if ! which tmux > /dev/null; then
    echo "This script requires tmux to be installed on a machine"
    exit 1
fi

# Cleanup artifact created in previous script run
rm -rf {cardano-node,tmux-server.log}

git clone git@github.com:input-output-hk/cardano-node.git
cd cardano-node
git checkout ${GIT_REV:-master}

# Cleanup artifacts created by Testnet script
rm -rf {logs,db,socket}

cd scripts

# Modify tmux script in repo - add vv flag for outputting tmux logs that scripts checks
# later for information proving testnet operates correctly and d flag for running in
# detach mode - this does NOT modify the logic of testnet script
mv lib-cluster.sh bak_lib-cluster.sh
cat bak_lib-cluster.sh | sed 's/tmux \\/tmux \\\n          -vv \\/' > tmp_lib-cluster.sh
cat tmp_lib-cluster.sh | sed 's/new-session \\/new-session \\\n          -d \\/' > lib-cluster.sh

cd ..

# Testnet will run for 10 minutes then tmux clien will shut down but tmux server will still be on
timeout 600 ./scripts/shelley-testnet.sh

# Script above needs some time to start up and generate logs with entries that are
# suggesting that testnet works and operate as expected - that's why the waiting with sleep
sleep 80

TMUX_LOG="$(ls -l |grep tmux-server-.*[0-9].log | awk '{ print $9 }')"
EXPECTED_LOG_ENTRIES="$(cat ${TMUX_LOG} | grep unByronHash |wc -l)"


if (( ${EXPECTED_LOG_ENTRIES} > 0 )); then
    echo "Number of entries in log suggesting testnet is running successfully: ${EXPECTED_LOG_ENTRIES}"
    exit 0
fi

echo "Error: no log entries, looks like local testnet script could be broken"
# This will kill tmux server (if logs suggest that Testnet is not running correctly)
# which runs on default socket located in /tmp/tmux-1000 so if machine on which this script will
# be run has other tmux sessions - they will be terminated, or should be created with different
# than default socket file as I am not modyfying currently the testnet tmux script to use different
# socket
tmux kill-server
exit 1
