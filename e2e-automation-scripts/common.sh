#!/bin/bash

export CARDANO_NODE_SOCKET_PATH='example/node-pool1/node.sock'
export testnet_magic=42
export root_dirpath=example
export genesis_filepath=$root_dirpath/genesis.json
export protocol_params_filepath=$PWD/$root_dirpath/protocol-params.json
export address_counter_filepath=$root_dirpath/address_counter
export pool_counter_filepath=$root_dirpath/pool_counter
export addresses_root_dirpath=$root_dirpath/addresses
export pool_1_dirpath=$root_dirpath/node-pool1

# user1 is created by mkfiles script and owns all the funds in the system
# so it is used as default source for all tx in test scripts

export user1_payment_signing_keypath=$addresses_root_dirpath/user1.skey
export user1_payment_vrf_keypath=$addresses_root_dirpath/user1.vkey
export user1_payment_address_path=$addresses_root_dirpath/user1.addr
export user1_payment_address=$(cat $user1_payment_address_path)
# create an alias from_address == user1_payment_address
export from_address=$user1_payment_address

# Message colors

color_reset='\033[0m' # No Color
green='\033[1;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
red='\033[1;31m'

# Block comment template

: <<'END'
    Block comment template
END

if [ -f $address_counter_filepath ]; then
    address_counter_value=$(cat $address_counter_filepath)
    export address_counter_value=$address_counter_value
fi

if [ -f $pool_counter_filepath ]; then
    pool_counter_value=$(cat $pool_counter_filepath)
    export pool_counter_value=$pool_counter_value
fi

error_msg() {
    printf "${red}$(date +%F.%T) ${BASH_SOURCE[1]##*/} line ${BASH_LINENO[0]} ERROR: ${@}${color_reset} \n" > /dev/tty
}

info_msg() {
    printf "${blue}INFO:${color_reset} ${@} \n" > /dev/tty
}

warn_msg() {
    printf "${yellow}WARNING:${color_reset} ${@} \n" > /dev/tty
}

success_msg() {
    printf "${green}SUCCESS:${color_reset} ${@} \n" > /dev/tty
}

# Checks if required number of arguments were passed to function - private internal for common.sh function
# Expects:
# 1) input param - number of required arguments [natural > 0]
# 2) optional - listed arguments that will be displayed to user if function used incorrectly
# Example: _check_number_of_arguments 2 '1) actual address' '2) expected balance - natural number [ADA]'

_check_number_of_arguments () {
    number_of_required_arguments=$1
    # Need to add 1 as we are also specyyfying the expcted number of arguments as an argument
    # apart other required arguments
    if (( $# != ( number_of_required_arguments + 1 ) )); then
        error_msg "Incorrect number of arguments."
        error_msg "Expected $number_of_required_arguments arguments:"

        for arg in "${@:2}"; do
                # double quotes around 'arg' required
                info_msg "$arg"
        done
        exit 1
    fi
}

# No arguments expected

check_address_counter_file () {
    if [ -f $address_counter_filepath ]; then
        info_msg "Counter file ${address_counter_filepath} exists - read the counter and increment by 1"
        address_counter_value=$(cat $address_counter_filepath)
        export address_counter_value=$(( address_counter_value + 1 ))
        echo $address_counter_value > $address_counter_filepath
        info_msg "Current run for $address_counter_filepath: $address_counter_value"
    else
        info_msg "Counter file $address_counter_filepath does NOT exist - initializing it with value 2"
        touch $address_counter_filepath
        echo 2 > $address_counter_filepath
        export address_counter_value=2
    fi
}

# No arguments expected

check_pool_counter_file () {
    if [ -f $pool_counter_filepath ]; then
        info_msg "Counter file $pool_counter_filepath exists - read the counter and increment by 1"
        pool_counter_value=$(cat $pool_counter_filepath)
        export pool_counter_value=$(( pool_counter_value + 1 ))
        echo $pool_counter_value > $pool_counter_filepath
        info_msg "Pool current run for $pool_counter_filepath: $pool_counter_value"
    else
        info_msg "Counter file $pool_counter_filepath does NOT exist - initializing it with value 2"
        touch $pool_counter_filepath
        echo 2 > $pool_counter_filepath
        export pool_counter_value=2
    fi
}

# No arguments expected

get_protocol_params () {
    local query_params=$(cardano-cli shelley query protocol-parameters \
        --testnet-magic $testnet_magic \
        --out-file $protocol_params_filepath
    )

    if [ $?	!= 0 ]; then
        error_msg "Error when querying protocol parameters"
        exit 1
    fi

    if [ ! -f $protocol_params_filepath ]; then
        error_msg "protocol params file was not created"
        exit 1
    fi

    exit 0
}

# No arguments expected

get_current_tip () {
    local current_tip=$(cardano-cli shelley query tip --testnet-magic $testnet_magic | awk -F= '{print $2}' | grep -o '[0-9]\+')

    if [ $? != 0 ]; then
        error_msg "Error when querying tip"
        exit 1
    fi

    if (( current_tip	< 1 )); then
        error_msg "Tip is at location: $current_tip"
        exit 1
    fi

    echo $current_tip
    exit 0
}

# No arguments expected

get_pool_deposit () {
    $(get_protocol_params)

    if [ $? != 0 ]; then
        error_msg "Error when obtaining protocol params"
        exit 1
    fi

    local pool_deposit=$(cat $protocol_params_filepath | jq '.poolDeposit')

    if (( pool_deposit	< 1 )); then
        warn_msg "Pool deposit is less than 1: $pool_deposit"
        # We will decide later whether change to ERROR and exit in such case or
        # display only WARNING
        # exit 1
    fi

    echo $pool_deposit
    exit 0
}

# No arguments expected

get_key_deposit () {
    $(get_protocol_params)

    if [ $? != 0 ]; then
        error_msg "Error when obtaining protocol params"
        exit 1
    fi

    local key_deposit=$(grep keyDep $protocol_params_filepath | grep -o '[0-9]\+')

    if (( key_deposit	< 1 )); then
        warn_msg "Key deposit is: $key_deposit"
        # We will decide later whether change to ERROR and exit in such case or
        # display only WARNING
        # exit 1
    fi

    echo $key_deposit
    exit 0
}

# No arguments expected

get_slots_per_kes_period () {
    local slots_per_kes_period=$(cat $genesis_filepath | grep KESPeriod |grep -o '[0-9]\+')

    if (( slots_per_kes_period	< 1 )); then
        error_msg "Number of slots per KES period is less than 1: $slots_per_kes_period"
        exit 1
    fi

    echo $slots_per_kes_period
    exit 0
}

# No arguments expected

calculate_kes_period () {
    local current_tip=$(get_current_tip)

    if [ $? != 0 ]; then
        error_msg "Error when getting current tip"
        exit 1
    fi

    local slots_per_kes_period=$(get_slots_per_kes_period)
    local kes_period=$(( current_tip / slots_per_kes_period ))

    echo $kes_period
    exit 0
}

# No arguments expected

calculate_ttl () {
    local tip=$(get_current_tip)

    if [ $? != 0 ]; then
        error_msg "Error when getting current tip"
        exit 1
    fi

    local ttl=$((tip + 10000))

    echo $ttl
    exit 0
}

# Expects 1 input param - an actual address number

get_tx_info_for_address () {
    local query_address=$1
    local tx=$(cardano-cli shelley query utxo --testnet-magic $testnet_magic --address $query_address | grep "^[^- ]" | sort -k 2n | tail -1)

    if [ $? != 0 ]; then
        error_msg "Error when performing query utxo on $query_address"
        exit 1
    fi

    echo $tx
    exit 0
}

# Expects 1 input param - a tx in format returned by get_tx_info_for_address

get_input_for_tx () {
    _check_number_of_arguments 1 '1) tx in format returned by get_tx_info_for_address'
    local utxo=$1
    local id=$2
    local input="${utxo}#${id}"

    echo $input
    exit 0
}

# Expects 1 input param - a tx in format returned by get_tx_info_for_address

get_balance_for_tx () {
    _check_number_of_arguments 1 '1) tx in format returned by get_tx_info_for_address'
    local balance=$3

    echo $balance
    exit 0
}

# No arguments expected

get_slot_length () {
    local slot_length_decimal="$(cat $genesis_filepath | grep slotLength | grep -Eo '[0-9]+\.[0-9]+')"
    info_msg "Original slot length: $slot_length_decimal"

    local slot_length_integer=$(echo $slot_length_decimal | awk -F. '{print $1}')
    info_msg "Slot length after decimal part removal: $slot_length_integer"

    echo $slot_length_integer
    exit 0
}

# No required arguments expected in this wait with polling function
# Optional argument - timeout measuerd in slots number to wait for result [natural]
# By default 200 slots will be used for timeout value

wait_for_new_tip () {
    local timeout_no_of_slots=$1
    timeout_no_of_slots=${timeout_no_of_slots:=200}
    local slot_length=$(get_slot_length)

    if (( slot_length < 1 )); then
        warn_msg "Slot length taken from $genesis_filepath was less than 1"
        info_msg "Setting slot length to 1"
        slot_length=1
    fi

    local counter=$(( slot_length * timeout_no_of_slots ))
    local initial_tip=$(get_current_tip)
    local actual_tip=$(get_current_tip)
    info_msg "Initial Slot Number: $initial_tip"

    while (( actual_tip == initial_tip )); do
        sleep $slot_length
	      actual_tip=$(get_current_tip)
	      counter=$((counter - 1))
	      if (( counter < 2 )); then
	          error_msg "Waited for $counter secs but no new block was created"
            error_msg "Exiting"
	          exit 1
	      fi
    done
    local total_waiting_time=$(( timeout_no_of_slots - counter ))
    info_msg "Waiting for max $timeout_no_of_slots slots. Finished after $total_waiting_time slots"
    info_msg "New block was created. New Slot Number: $actual_tip"
}

# Expects 1 input params:
# actual address - address number

check_address_details () {
    _check_number_of_arguments 1 '1) actual address'
    local query_address=$1
    local address_details=$(get_tx_info_for_address $query_address)

    if [ $? != 0 ]; then
        error_msg "Error when checking transaction details"
        exit 1
    fi

    if [[ -z $address_details || $address_details == *"----"* ]]; then
        error_msg "Address $query_address does not exist / empty."
        error_msg "Exiting ..."
        exit 2
    fi

    info_msg "Address details: $address_details"

    echo $address_details
    exit 0
}

# Expects 2 input params:
# 1) actual address - address number
# 2) expected balance - natural number

assert_address_balance () {
    _check_number_of_arguments 2 '1) actual address' '2) expected balance - natural number [ADA]'

    info_msg "Asserting address balance ..."

    local query_address=$1
    local expected_balance=$2
    local address_details=$(check_address_details $query_address)

    if [ $? != 0 ]; then
        error_msg "Error when checking address details"
        exit 2
    fi

    local actual_balance=$(get_balance_for_tx $address_details)

    if [ $? != 0 ]; then
        error_msg "Error when obtaining address balance"
        exit 3
    fi

    if (( actual_balance != expected_balance )); then
        error_msg "Incorrect amount of funds on address. Is: $actual_balance. Should be: $expected_balance"
        exit 4
    fi

    success_msg "Balance check correct: $expected_balance lovelaces"
    exit 0
}

exec "$@"
