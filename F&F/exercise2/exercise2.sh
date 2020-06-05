#!/bin/bash

function usage()
{
cat << HEREDOC

    Usage: $progname [--help] [--from] [--to] [--amount]

    optional arguments:
      -h, --help           show this help message and exit
      -f, --from           source address from which we will be sending money
                           WARNING: If you specify -f you also need to specify a signing key -s for it
      -s, --signing-key    signing key location for source address
      -t, --to             destination address to which we will send money
      -a, --amount         amount

Script for exercise 2 from Cardano Tutorials:
https://github.com/input-output-hk/cardano-tutorials/blob/master/pioneers-testnet/pioneers-exercise-2.md

Requirements:
0) Running relay node, socket file relay/db/node.socket must exist
1) GHC, cabal and all libs needed to start node. (Check tutorials docs)
2) Required ports to be opened

The purpose of this script is to create, sign and submit a transaction - if you don't use any arguments then by default transfer will be made from payment1.addr created in exercise 1 to payment2.addr - created by this script.

It also builds stake address - stake2.addr - that will be used in different exercises.

It first creates address 2 - a destination address for money transfer - and then creates transaction that sends ADA from address 1 ( it should already have funds coming from faucet ) to address 2.

All directories are created inside cardano-node:

exercise2/keys_and_addresses


To check if your money was sent to address 2 use:

export CARDANO_NODE_SOCKET_PATH=path/to/cardano-node/db/node.socket
cardano-cli shelley query utxo --address your_address_2 --testnet-magic 42

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

# Current working dir for exercise 2

CWD="${PWD}"
cd ..

# Initialize variables

progname=$(basename $0)
files_created_by_script_dirname=keys_and_addresses
socket_file="${PWD}/relay/db/node.socket"
time_interval=30
lock_file=lock
counter_file=counter
testnet_magic=42

# Default values

from=$(cat "exercise1/keys_and_addresses/payment1.addr")
signing_key="exercise1/keys_and_addresses/payment1.skey"
amount=1000000 # 1 ADA
raw_tx_filename="tx001-send-ada-from-addr1-to-addr2.raw"
signed_tx_filename="tx001-send-ada-from-addr1-to-addr2.signed"

OPTS=$(getopt -o "hf:s:t:a:" --long "help,from:signing-key:to:amount:" -n "$progname" -- "$@")

if [ $? != 0 ] ; then
    echo "Error in command line arguments." >&2 ; usage; exit 1 ;
fi

eval set -- "$OPTS"

while true; do
    case "$1" in
        -h | --help ) usage; exit; ;;
        -f | --from ) from="$2"; shift 2 ;;
        -s | --signing-key ) signing_key="$2"; shift 2 ;;
        -t | --to ) to="$2"; shift 2 ;;
        -a | --amount ) amount="$2"; shift 2 ;;
        -- ) shift; break ;;
        * ) break ;;
    esac
done


# Check whether node is running

is_node_running="$(ps -aux |grep "[c]ardano-node run" | wc -l)"

if [[ "${is_node_running}" < 1 || ! -S "${socket_file}" ]]; then
    requiremnts
fi


# Export CARDANO_NODE_SOCKET_PATH that will be used with cardano-cli

export CARDANO_NODE_SOCKET_PATH="${PWD}/relay/db/node.socket"


# Lets create counter file that will keep the number of how many times this script was ran
# that will be used to create separate directories for each script run

if [ -f "${CWD}/${counter_file}" ]; then
    echo "INFO: Counter file exist - read the counter and increment by 1"
    counter_value=$(cat "${CWD}/${counter_file}")
    counter_value=$((counter_value+1))
    echo ${counter_value} > "${CWD}/${counter_file}"
    echo "INFO: Current run: ${counter_value}"

else
    echo "INFO: Counter file does NOT exist - initializing it with value 0"
    touch "${CWD}/${counter_file}"
    echo 0 > "${CWD}/${counter_file}"
    counter_value=0
fi

# Create directory for payment key pair and address files

current_files_dir=${CWD}/${files_created_by_script_dirname}/${counter_value}
echo -e "\nINFO: Creating directory: ${current_files_dir} for payment key pair and address files ..."
mkdir -p "${current_files_dir}"


# Create payment key pair

echo "INFO: Creating Payment Key Pair ..."

cardano-cli shelley address key-gen \
    --verification-key-file "${current_files_dir}/payment2.vkey" \
    --signing-key-file "${current_files_dir}/payment2.skey"

if [ $?	!= 0 ]; then
    echo "ERROR: Error during payment 2 keypair creation"
    exit 1
fi

# Generate stake key pair

echo "INFO: Creating Stake Key Pair ..."

cardano-cli shelley stake-address key-gen \
    --verification-key-file "${current_files_dir}/stake2.vkey" \
    --signing-key-file "${current_files_dir}/stake2.skey"

if [ $?	!= 0 ]; then
    echo "ERROR: Error during stake 2 keypair creation"
    exit 1
fi

# Build payment address

echo "INFO: Creating Payment Address ..."

cardano-cli shelley address build \
    --payment-verification-key-file "${current_files_dir}/payment2.vkey" \
    --stake-verification-key-file "${current_files_dir}/stake2.vkey" \
    --out-file "${current_files_dir}/payment2.addr"

if [ $?	!= 0 ]; then
    echo "ERROR: Error during payment 2 address creation"
    exit 1
fi

# Check if destination 'to' address was set - if not - use default one

if [ -z "${to}" ]; then
    echo "destination address 'to' not set, using defaut one: "${current_files_dir}/payment2.addr""
    to=$(cat "${current_files_dir}/payment2.addr")
fi

# Build stake address

echo "INFO: Creating Stake Address ..."

cardano-cli shelley stake-address build \
    --staking-verification-key-file "${current_files_dir}/stake2.vkey" \
    --out-file "${current_files_dir}/stake2.addr"

if [ $?	!= 0 ]; then
    echo -e "\nERROR: Error during stake 2 address creation"
    exit 1
fi


# Get current protocol params

protocol_params_file="${CWD}/protocol.json"

echo -e "\nINFO: Get current protocol params: ${protocol_params_file} ..."

cardano-cli shelley query protocol-parameters \
    --testnet-magic "${testnet_magic}" \
    --out-file "${protocol_params_file}"

if [ $?	!= 0 ]; then
    echo -e "\nERROR: Error when querying protocol parameters"
    exit 1
fi

# Show balance for addresses before making transaction

echo -e "\nINFO: Showing balance for source address before TX ..."

output_for_source_addr_before_tx=$(cardano-cli shelley query utxo \
    --address "${from}" \
    --testnet-magic "${testnet_magic}" )

#Check if status line with values is not empty or is "------------------------------------"

source_addr_stats_before_tx=$(echo "${output_for_source_addr_before_tx}" | head -3 | tail -1)

if [[ -z "${source_addr_stats_before_tx}" || "${source_addr_stats_before_tx}" == *"----"* ]]; then
    echo -e "\nsource address ${from} not present yet on the blockchain, you need to wait longer.
    Exiting ..."
    exit 0
else
    echo -e "\n$source_addr_stats_before_tx"
fi

echo -e "\nINFO: Showing balance for destination address before TX ..."

output_for_destination_addr_before_tx=$(cardano-cli shelley query utxo \
    --address "${to}" \
    --testnet-magic "${testnet_magic}" )

destination_addr_stats_before_tx=$(echo "${output_for_destination_addr_before_tx}" | head -3 | tail -1)
if [[ -z "${destination_addr_stats_before_tx}" || "${destination_addr_stats_before_tx}" == *"----"* ]]; then
    echo -e "\ndestination address ${to} not present yet on the blockchain, you need to wait longer.
    Exiting ..."
    exit 0
else
    echo -e "\n$destination_addr_stats_before_tx"
fi

# Determine TTL

current_tip="$(cardano-cli shelley query tip --testnet-magic "${testnet_magic}" | awk -F= '{print $2}' | grep -o '[0-9]\+')"
ttl="$(($current_tip+100000))"

echo -e "\nCurrent tip: ${current_tip}"
echo "Setting TTL to: ${ttl}"


# Calculate fee

echo -e "\nCalculating TX fee ..."

fee=$(cardano-cli shelley transaction calculate-min-fee \
    --tx-in-count 1 \
    --tx-out-count 2 \
    --ttl "${ttl}" \
    --testnet-magic 42 \
    --signing-key-file "${signing_key}" \
    --protocol-params-file "${protocol_params_file}" \
    | awk '{ print $2}')

echo "Fee: ${fee}"


# By default use address 1 from exercise 1 as a source address

tx=$(cardano-cli shelley query utxo --testnet-magic "${testnet_magic}" --address "${from}" | grep "^[^- ]" | sort -k 2n | tail -1)

echo -e "\nTX: $tx "
utxo=$( echo "$tx" | awk '{ print $1 }')
id=$( echo "$tx" | awk '{ print $2 }')
balance=$( echo "$tx" | awk '{ print $3 }')
input="${utxo}#${id}"

change=$(( ${balance} - ${fee} - ${amount}))

echo -e "\nTX Info:"
echo "Input: ${input}"
echo "Balance: ${balance}"
echo "Change: ${change}"
echo -e "\nINFO: Sending $(($amount/1000000)) ADA from ${from} to ${to}"


# Transaction creation

# Build TX

cardano-cli shelley transaction build-raw \
    --tx-in "${input}" \
    --tx-out "${from}+${change}" \
    --tx-out "${to}+${amount}" \
    --ttl "${ttl}" \
    --fee "${fee}" \
    --tx-body-file "${current_files_dir}/${raw_tx_filename}"

#Sign TX

cardano-cli shelley transaction sign \
    --tx-body-file "${current_files_dir}/${raw_tx_filename}" \
    --signing-key-file "${signing_key}" \
    --testnet-magic "${testnet_magic}" \
    --out-file "${current_files_dir}/${signed_tx_filename}"

#Submit TX

cardano-cli shelley transaction submit \
    --tx-file "${current_files_dir}/${signed_tx_filename}" \
    --testnet-magic "${testnet_magic}"

# Issue with cli return status

if [ $?	== 0 ]; then
    echo -e "\nERROR: Error when submitting transaction"
    exit 1
fi

# Wait for some time

echo -e "\nINFO: Waiting for 20 seconds ..."

sleep 20

# Check addresses

echo -e "\nINFO: Checking balance for address 1 after TX:"

cardano-cli shelley query utxo --address "${from}" --testnet-magic "${testnet_magic}"

echo -e "\nINFO: Checking balance for address 2 after TX:"

cardano-cli shelley query utxo --address "${to}" --testnet-magic "${testnet_magic}"

