#!/bin/bash

function usage()
{
    cat << HEREDOC

    Usage: $progname [--help] [--mode]

    optional arguments:
      -h, --help           show this help message and exit
      -m, --mode           run mode - possible options:
                          single-node (default)
                          blockproducer-relay


Script for exercise 1 from Cardano Tutorials:
https://github.com/input-output-hk/cardano-tutorials/blob/master/pioneers-testnet/pioneers-exercise-1.md

Requirements:
1) GHC, cabal, tmux and all libs needed to start node. (Check tutorials docs)
2) Ports 3000 - 3002 opened

This script creates config directory named ff-config then downloads config files for
F&F network into it.  It also creates block-producer and relay dirs for producer and relay nodes with all
the configs needed to start them.

Then - depending on the selected mode - it starts single node or producer and relay nodes
connected to F&F network. All directories are created inside cardano-node:

db
ff-config
block-producer
relay
exercise1/keys_and_addresses

In the end script creates payment key pair in order to genearte payment address
that will be supplied with 1 MLN ADA by sending request to faucet.
Once funds were transfered to your freshly created address you will need to wait for blockchain to
sync up to that point which may take a while if you are starting node(s) from scratch.

To check if your address was charged with money use:

export CARDANO_NODE_SOCKET_PATH=path/to/cardano-node/db/node.socket

cardano-cli shelley query utxo --address your_address --testnet-magic 42


WARNING: Everytime you run this script all state files will be removed and keys, addresses overwritten
so after you ran it for the first time lock file will be created.
It will prevent all those dir and files from being overwritten - so in order to re run it again:

1) backup your key/address files inside exercise1 folder, so they won't be overwritten
2) remove lock file and run script again.

HEREDOC
}

# Initialize variables

progname=$(basename $0)
files_created_by_script_dirname=keys_and_addresses
mode="single-node"
lock_file=lock

ff_relay_hostname=relays-new.ff.dev.cardano.org
ff_relay_port=3001

local_relay_hostname=127.0.0.1
local_relay_port=3000

local_block_producer_hostname=127.0.0.1
local_block_producer_port=3002


OPTS=$(getopt -o "hm:" --long "help,mode:" -n "$progname" -- "$@")
if [ $? != 0 ] ; then
    echo "ERROR: Error in command line arguments." >&2 ; usage; exit 1 ;
fi

eval set -- "$OPTS"

while true; do
    case "$1" in
        -h | --help ) usage; exit; ;;
        -m | --mode ) mode="$2"; shift 2 ;;
        -- ) shift; break ;;
        * ) break ;;
    esac
done

# Current working dir for exercise 1

CWD="${PWD}"
cd ..

# Check for lock file

if [ -f "${CWD}/${lock_file}" ]; then
    echo "INFO: Lock file exist meaning that you already ran this script and created key pairs and address to which ADA
          was sent. If you want to re-run this script backup all your keys, addres files in a separate directory and remove lock file.
          WARNING: Rerunning this script will remove all state files (db) and will overwrite existing keys inside exercise1 dir."
    exit 0;
fi

# Remove state and config direcories

echo "INFO: Removing state directories ..."
rm -rf db
rm -rf ff-config
rm -rf block-producer
rm -rf relay

# Create a directory for F&F configuration files

echo "\nINFO: Creating ff-config dirs ..."
mkdir ff-config

# Download F&F configuration files to ff-config directory using URLs specified inside urls-with-configs.txt file
# To completely turn off output from wget use -q option instead of -nv.
# To use full verbose output remove -nv from command below

echo "INFO: Downloading F&F config files to ff-config ..."
wget -nv -P ff-config -i "${CWD}/urls-with-configs.txt"


# create directories for block producing and relay node
# and copy config files

echo "\nINFO: Creating block-producer and relay dirs and copying configs into them ..."
mkdir {block-producer,relay}

cp ff-config/* block-producer
cp ff-config/* relay


echo "{
  \"Producers\": [
    {
      \"addr\": \"${local_block_producer_hostname}\",
      \"port\": ${local_block_producer_port},
      \"valency\": 1
    }
  ]
}" > block-producer/ff-topology.json



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
}" > relay/ff-topology.json

# Create directory for payment key pair and address files

echo "\nINFO: Creating directory: ${files_created_by_script_dirname} for payment key pair and address files ..."

mkdir "${CWD}/${files_created_by_script_dirname}"

# Create payment key pair in order to genearte payment address
# It will be used to transfer some initial funds from faucet (or other Pioneer)

echo "INFO: Creating payment 1 keypair ..."

cardano-cli shelley address key-gen \
    --verification-key-file "${CWD}/${files_created_by_script_dirname}/payment1.vkey" \
    --signing-key-file "${CWD}/${files_created_by_script_dirname}/payment1.skey"

if [ $?	!= 0 ]; then
    echo "ERROR: Error during payment 1 keypair creation"
    exit 1
fi

# Build address

echo "INFO: Creating payment 1 address ..."

cardano-cli shelley address build \
    --payment-verification-key-file "${CWD}/${files_created_by_script_dirname}/payment1.vkey" > "${CWD}/${files_created_by_script_dirname}/payment1.addr"

if [ $?	!= 0 ]; then
    echo "ERROR: Error payment 1 address creation"
    exit 1
fi

# Request 1 MLN from faucet for newly created address

echo "\nINFO: Requesting funds - 1 MLN ADA - ro be tranfered from faucet to payment 1 address ..."

# Known to Pioneers only - fill in and uncomment
#curl -v -XPOST "https://hostname/endpoint/$(cat "${CWD}/${files_created_by_script_dirname}/payment1.addr")?apiKey=key"

# Create lock file

echo "\nINFO: Creating lock file - so you will not accidentally remove/overwrite your keys and address files when running this script again ..."

touch "${CWD}/${lock_file}"

# Run single node connected to F&F network

if [ "${mode}" = "single-node" ]; then
    echo "INFO: Starting local single node ..."
    cardano-node run \
        --topology ff-config/ff-topology.json \
        --database-path db \
        --socket-path db/node.socket \
        --port 3001 \
        --config ff-config/ff-config.json
fi


# Otherwise run pool and relay inside tmux"

if [ "${mode}" = "blockproducer-relay" ]; then
    echo "INFO: Starting local block-producer and relay nodes ..."
    tmux has-session -t dev

    if [ $?	!= 0 ]; then
    tmux new-session -s dev -n "Cardano Pool & Relay Nodes" -d
    tmux split-window -h -t dev:0
    tmux send-keys -t dev:0.0 'cardano-node run --topology block-producer/ff-topology.json --database-path block-producer/db --socket-path block-producer/db/node.socket --port 3000 --config block-producer/ff-config.json' C-m
    tmux send-keys -t dev:0.1 'cardano-node run --topology relay/ff-topology.json --database-path relay/db --socket-path relay/db/node.socket --port 3002 --config relay/ff-config.json' C-m
    tmux select-window -t dev:0
    tmux attach -t dev
    fi
fi
