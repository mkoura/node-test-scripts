#!/bin/bash

function usage()
{
cat << HEREDOC

    Usage: $progname [--help]

    optional arguments:
      -h, --help           show this help message and exit


Script for exercise 3 from Cardano Tutorials:
https://github.com/input-output-hk/cardano-tutorials/blob/master/pioneers-testnet/pioneers-exercise-3.md

Requirements:
0) Running relay node, socket file relay/db/node.socket must exist
1) GHC, cabal, tmux and all libs needed to start node. (Check tutorials docs)
2) Required ports to be opened

The purpose of this script is to create "cold" and "hot" keys for a relay and stake pool node and then start them.

Directories created inside cardano-node:
pool
pool-relay

Directories created outside cardano-node:
/home/your-user-name/cold-keys

HEREDOC
}

function requiremnts()
{

cat << HERE_DOC
Looks like relay node is not running.
This script requires relay node from exercise 1 to be running.

It is located in: cardano-node/relay/
Socket file: cardano-node/relay/db/node.socket

You can start node by running "run-node.sh" script from cardano-node/exercise2 directory
OR by manually running from cardano-node directory in a separate terminal:

cardano-node run --topology relay/ff-topology.json --database-path relay/db --socket-path relay/db/node.socket --port 3002 --config relay/ff-config.json

HERE_DOC
exit 1
}

# Current working dir for exercise 3

CWD="${PWD}"
cd ..


# Initialize variables

progname=$(basename $0)
socket_file="${PWD}/relay/db/node.socket"
testnet_magic=42
files_created_by_script_dirname=keys_and_certs
lock_file=lock

ff_relay_hostname=relays-new.ff.dev.cardano.org
ff_relay_port=3001

local_relay_hostname=127.0.0.1
local_relay_port=4240

local_block_producer_hostname=127.0.0.1
local_block_producer_port=4242


OPTS=$(getopt -o "h" --long "help" -n "$progname" -- "$@")
if [ $? != 0 ] ; then
    echo "ERROR: Error in command line arguments." >&2 ; usage; exit 1 ;
fi

eval set -- "$OPTS"

while true; do
    case "$1" in
        -h | --help ) usage; exit; ;;
        -- ) shift; break ;;
        * ) break ;;
    esac
done


# Check whether node is running

is_node_running="$(ps -aux |grep "[c]ardano-node run" | wc -l)"

if [[ "${is_node_running}" < 1 || ! -S "${socket_file}" ]]; then
    requiremnts
fi

# Set CARDANO_NODE_SOCKET_PATH for cardano-cli tool

export CARDANO_NODE_SOCKET_PATH="relay/db/node.socket"


# Check for lock file

if [ -f "${CWD}/${lock_file}" ]; then
    echo "INFO: Lock file exist meaning that you already ran this script and created 'hot' and 'cold' KES, VRF key pairs.
          If you want to re-run this script backup all your cold keys, addresses etc. files in a separate directory and remove
          lockfile.
          WARNING: Rerunning this script after lockfile removal will overwrite existing 'cold', 'hot', KES, VRF keys and remove pool
          and relay directories with all its state"
    exit 0;
fi

echo "INFO: Removing pool, pool-relay and cold-keys directories ..."
rm -rf pool
rm -rf pool-relay
rm -rf ~/cold-keys

# Create two new directories for pool and its relay and copy the configuration files to them

echo "INFO: Creating two new directories for pool and its relay and copying the configuration files into them ..."
echo "INFO: Directory locations:"
echo "${PWD}/pool"
echo "${PWD}/pool-relay"

mkdir {pool,pool-relay}

cp ff-config/* pool
cp ff-config/* pool-relay

# Create a new directory to hold your "cold" keys

echo -e "\nINFO: Creating 'cold-keys' direcory inside ${HOME} for storing 'cold' keys and generating 'cold' keys ..."

mkdir ~/cold-keys
pushd ~/cold-keys

# Generate  offline "cold" key pair

cardano-cli shelley node key-gen \
    --verification-key-file "cold.vkey" \
    --signing-key-file "cold.skey" \
    --operational-certificate-issue-counter "cold.counter"

echo "INFO: Content of ${PWD}"
ls -l

echo -e "\nINFO: Moving back to:"
popd

# Create directory for keys and certs inside pool dir

current_files_dir=${PWD}/pool/${files_created_by_script_dirname}
echo -e "\nINFO: Creating directory: ${current_files_dir} for payment key pair and address files ..."
mkdir -p "${current_files_dir}"

# Generate hot KES keypair

echo -e "\nINFO: Generating hot KES keypair ..."

cardano-cli shelley node key-gen-KES \
    --verification-key-file "${current_files_dir}/kes.vkey" \
    --signing-key-file "${current_files_dir}/kes.skey"


# Calculate start of KES validity period

echo -e "\nINFO: Calculating KES period ..."

slots_per_kes_period="$(cat ff-config/ff-genesis.json | grep KESPeriod |grep -o '[0-9]\+')"
current_tip="$(cardano-cli shelley query tip --testnet-magic "${testnet_magic}" | awk -F= '{print $2}' | grep -o '[0-9]\+')"

kes_period="$((${current_tip} / ${slots_per_kes_period}))"

echo "KES period: ${kes_period}"

# Create operational certificate for your pool

echo -e "\nINFO: Creating operational certificate for your pool ..."

cardano-cli shelley node issue-op-cert \
    --kes-verification-key-file "${current_files_dir}/kes.vkey" \
    --cold-signing-key-file ~/cold-keys/cold.skey \
    --operational-certificate-issue-counter ~/cold-keys/cold.counter \
    --kes-period "${kes_period}" \
    --out-file "${current_files_dir}/opcert"

# Make sure that no-one can access "cold" keys

# chmod a-rwx ~/cold-keys

# Generate a VRF key pair for your new stake pool - they will be used for leader lottery selection

echo -e "\nINFO: Generating a VRF key pair for your new stake pool ..."

cardano-cli shelley node key-gen-VRF \
    --verification-key-file "${current_files_dir}/vrf.vkey" \
    --signing-key-file "${current_files_dir}/vrf.skey"


echo -e "\nINFO: Content of ${current_files_dir}"
ls -l "${current_files_dir}"

# Create lock file

echo -e "\nINFO: Creating lock file - so you will not accidentally remove/overwrite your keys and address files when running this script again ..."

touch "${CWD}/${lock_file}"

# Create topology files for pool and relay

echo -e "\nINFO: Adjusting settings inside topology files for pool and relay ..."

echo "{
   \"Producers\": [
     {
       \"addr\": \"${local_block_producer_hostname}\",
       \"port\": ${local_block_producer_port},
       \"valency\": 1
     }
   ]
 }" > pool/ff-topology.json



 echo "{
   \"Producers\": [
     {
       \"addr\": \"${local_relay_hostname}\",
       \"port\": ${local_relay_port},
       \"valency\": 1
     },
     {
       \"addr\": \"${ff_relay_hostname}\",
       \"port\": ${ff_relay_port},
       \"valency\": 1
     }
   ]
 }" > pool-relay/ff-topology.json


echo -e "\nINFO: Starting pool and relay nodes in tmux session ..."

tmux has-session -t dev

if [ $? != 0 ]; then
    tmux new-session -s dev -n "Cardano Pool & Relay Nodes" -d
    tmux split-window -h -t dev:0
    tmux send-keys -t dev:0.0 "cardano-node run --config pool/ff-config.json --topology pool/ff-topology.json --database-path pool/db --socket-path pool/db/node.socket --shelley-kes-key ${current_files_dir}/kes.skey --shelley-vrf-key ${current_files_dir}/vrf.skey --shelley-operational-certificate ${current_files_dir}/opcert --port ${local_relay_port}" C-m
    tmux send-keys -t dev:0.1 "cardano-node run --topology pool-relay/ff-topology.json --database-path pool-relay/db --socket-path pool-relay/db/node.socket --port ${local_block_producer_port} --config pool-relay/ff-config.json" C-m
    tmux select-window -t dev:0
fi
tmux attach -t dev
