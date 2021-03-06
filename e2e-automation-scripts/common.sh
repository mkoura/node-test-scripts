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

exec 3>&1

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
    printf "${red}$(date +%F.%T) ${BASH_SOURCE[1]##*/} line ${BASH_LINENO[0]} ERROR: ${@}${color_reset} \n" >&3
}

info_msg() {
    printf "${blue}INFO:${color_reset} ${@} \n" >&3
}

warn_msg() {
    printf "${yellow}WARNING:${color_reset} ${@} \n" >&3
}

success_msg() {
    printf "${green}SUCCESS:${color_reset} ${@} \n" >&3
}

# Expects 1 argument - number of characters to generate

get_random_hex_string () {
    local number_of_chars=$1
    local random_hex_string=$(tr -dc 'a-f0-9' < /dev/urandom | head -c$number_of_chars)

    echo $random_hex_string
}

# No arguments expected

get_random_payment_address () {
    local header=00 # 8 bit shelley payment address header
    local random_hex_string=$(get_random_hex_string 129) # remaining part of address
    local random_address="$header$random_hex_string"

    echo $random_address
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

# Returns all the UTXOs for the specified address
# Expects 1 input param - an address number

get_utxos_for_address () {
    _check_number_of_arguments 1 '1) Shelley payment address'
    local query_address=$1
    local all_utxos=$(cardano-cli shelley query utxo --testnet-magic $testnet_magic --address $query_address | grep "^[^- ]")

    if [ $? != 0 ]; then
        error_msg "Error when performing query utxo on $query_address"
        exit 1
    fi

    echo "${all_utxos}"
    exit 0
}

# Returns the number of UTXOs for the specified address
# Expects 1 input param - an address number

get_no_of_utxos_for_address () {
    _check_number_of_arguments 1 '1) Shelley payment address'
    local query_address=$1
    local all_utxos=$(get_utxos_for_address $query_address)

    readarray -t utxo_array <<<"$all_utxos"

    echo ${#utxo_array[@]}
    exit 0
}

# Returns the balance of the specified address (the sum of all UTXOs of the specified address)
# Expects 1 input param - an address number

get_address_balance () {
    _check_number_of_arguments 1 '1) Shelley payment address'
	local query_address=$1
	local all_utxos=$(get_utxos_for_address $query_address)
	local balance=0

	readarray -t utxo_array <<<"$all_utxos"

	for utxo_string in "${utxo_array[@]}"; do
		utxo_amount=$(echo $utxo_string | cut -d' ' -f3)
		balance=$(( balance + utxo_amount))
	done

	echo $balance
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
    local slot_length="$(cat $genesis_filepath | grep slotLength | grep -Eo '[0-9]+\.[0-9]+')"
    info_msg "Slot length: $slot_length"

    echo $slot_length
    exit 0
}

# No required arguments expected in this wait with polling function
# Optional argument - timeout measuerd in slots number to wait for result [natural]
# By default 200 slots will be used for timeout value

wait_for_new_tip () {
    local timeout_no_of_slots=$1
    timeout_no_of_slots=${timeout_no_of_slots:=200}
    local slot_length=$(get_slot_length)

    local initial_tip=$(get_current_tip)
    local actual_tip=$(get_current_tip)
    info_msg "Initial Slot Number: $initial_tip"
    local counter=$timeout_no_of_slots

    while (( actual_tip == initial_tip )); do
        sleep $slot_length

        actual_tip=$(get_current_tip)
		    counter=$((counter - 1))

        if (( counter < 2 )); then
			      error_msg "Waited for $counter slots but no new block was created"
			      error_msg "Exiting"
			      exit 1
		    fi
    done
    local total_waiting_time=$(( timeout_no_of_slots - counter ))
    info_msg "Waiting for max $timeout_no_of_slots slots. Finished after $((timeout_no_of_slots - counter)) slots"
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

    local actual_balance=$(get_address_balance $query_address)

    if [ $? != 0 ]; then
        error_msg "Error when obtaining address balance"
        exit 3
    fi

    if (( actual_balance != expected_balance )); then
        error_msg "Incorrect amount of funds for address. Is: $actual_balance. Should be: $expected_balance"
        exit 4
    fi

    success_msg "Balance check correct: $expected_balance lovelaces"
    exit 0
}

# Expects 3 input params:
# number of inputs - address number
# number of outputs - address number
# signing keys - array of the signing key locations
calculate_tx_fee () {
    _check_number_of_arguments 3 '1) number of inputs' '2) number of outputs' '3) signing key files'

	local tx_in_count=$1
	local tx_out_count=$2
	local signing_keys=$3

	readarray -t signing_keys_array <<<"$signing_keys"

	# Determine TTL
	current_tip=$(get_current_tip)

	if [ $? != 0 ]; then
		error_msg "Error when getting current tip"
		exit 1
	fi

	ttl=$(calculate_ttl)

	# Get current protocol params and write it to file
	$(get_protocol_params)

	if [ $?	!= 0 ]; then
		error_msg "Error getting the protocol parameters"
		exit 1
	fi

	local counter=0
	for signing_key in "${signing_keys_array[@]}"; do
		signing_key_args[counter]=$(echo "--signing-key-file $signing_key ")
		counter=$(( counter + 1 ))
	done

	fee=$(cardano-cli shelley transaction calculate-min-fee \
		--tx-in-count $tx_in_count \
		--tx-out-count $tx_out_count \
		--ttl $ttl \
		--testnet-magic $testnet_magic \
		${signing_key_args[@]} \
		--protocol-params-file $protocol_params_filepath \
		| awk '{ print $2}')

	echo $fee
	exit 0
}

# Sends funds from 1 or multiple (array) payment addresses to 1 or multiple (array) payment addresses
# Expects 4 input params:
# 1) source address array - 1 or more source addresses
# 2) destination address array - 1 or more destination addresses
# 3) amount transferred - amounts array [LOVELACE or ALL] to be transfered from source_addresse to destination_addresses
# 3.1) if there are not enough funds in the UTXO with the highest amount (of the source address), but there are enough funds
# into the address, all the UTXOs of the source address will be used into the trasaction
# 4) signing keys array - 1 or more signing key of the source address(es)
# TO DO: it does not work when having multiple source addresses
# Usage example (1 source, 2 destinations, 2 amounts, 1 signning key):
#		send_funds 1 $from_address 2 $to_address 2 $tx_amount 1 $signing_key (1 checks)

send_funds_many_dsts () {
    _check_number_of_arguments 4 '1) source addresses array' '2) destination addresses array' '3) amounts transferred array' '4) signing keys array'

	# creating tmp_tx folder to keep the tx files until they are submitted
	if [ -d $root_dirpath/tmp_txs ]; then
		rm -Rf $root_dirpath/tmp_txs
	else
		mkdir $root_dirpath/tmp_txs
	fi

	raw_tx_filepath=$root_dirpath/tmp_txs/tx-body.raw
	signed_tx_filepath=$root_dirpath/tmp_txs/tx-body.signed

	declare -i num_args
	declare -a curr_args src_address_array dst_address_array amount_transferred_array signing_keys_array

	local checks=false
	local counter=0
	while (( $# )) ; do
		curr_args=( )
		num_args=$1; shift

		while (( num_args-- > 0 )) ; do
			curr_args+=( "$1" ); shift
		done

		if [ $counter == 0 ]; then
			src_address_array=("${curr_args[@]}")
		elif [[ $counter == 1 ]]; then
			dst_address_array=("${curr_args[@]}")
		elif [[ $counter == 2 ]]; then
			amount_transferred_array=("${curr_args[@]}")
		elif [[ $counter == 3 ]]; then
			signing_keys_array=("${curr_args[@]}")
		fi
		counter=$(( counter + 1 ))
	done

	if [ ${#src_address_array[@]} != 1 ]; then
		# TO DO: if there would be more than 1 source address, we would need to decide how much to take from each of the UTXOs of each address
		# This would be more like a contract than a transaction
		error_msg "send_funds could be used only with 1 source address; actual: ${#src_address_array[@]}"
		exit 1
	fi

	if [ ${#dst_address_array[@]} != ${#amount_transferred_array[@]} ]; then
		# dst_address_array[0] -> amount_transferred_array[0], etc
		error_msg "the number of destination addresses is different then the number of destination amounts; \
		${#dst_address_array[@]} != ${#amount_transferred_array[@]}"
		exit 1
	fi

	# Determine TTL
	current_tip=$(get_current_tip)

	if [ $? != 0 ]; then
		error_msg "Error when getting current tip"
		exit 1
	fi

	ttl=$(calculate_ttl)

	# Get current protocol params and write it to file
	$(get_protocol_params)

	if [ $?	!= 0 ]; then
		error_msg "Error when obtaining protocol parameters"
		exit 1
	fi

	# Get the number of UTXOs available in the first address from the src_address_array
	no_of_utxos=$(get_no_of_utxos_for_address ${src_address_array[0]})

	if [ $? != 0 ]; then
		error_msg "Error while getting the number of UTXOs for address: ${src_address_array[0]}"
		exit 1
	fi

	# Estimate the tx fee value base on the number of UTXOs inside the source address
	local tx_in_count=$no_of_utxos
	# ussually there is a change/rest (so those funds will return to the source address)
	local tx_out_count=$(( ${#dst_address_array[@]} + 1 ))

	fee=$(calculate_tx_fee $tx_in_count $tx_out_count ${signing_keys_array[@]})

	# Get the UTXO with the highest value inside the source address
	# Get UTXOs for first address from the src_address_array (to be used into the actual transaction)
	local src_utxos=$(get_utxos_for_address ${src_address_array[0]})
	local highest_amount_utxo=0
	local utxo_no=0
	local counter=0

	# Create an array with all the utxos from first address from the src_address_array
	readarray -t utxo_array <<<"$src_utxos"

	# Get the value and array_index of the UTXO with the highest amount of LOVELACE from first address from the src_address_array
	for utxo_string in "${utxo_array[@]}"; do
		utxo_amount=$(echo $utxo_string | cut -d' ' -f3)
		if (( utxo_amount >= highest_amount_utxo )); then
			highest_amount_utxo=$utxo_amount
			utxo_no=$counter
		fi
		counter=$(( counter + 1 ))
	done

	highest_amount_utxo=${utxo_array[$utxo_no]}
	highest_utxo_amount_balance=$(get_balance_for_tx $highest_amount_utxo)
	src_addr_balance=$(get_address_balance ${src_address_array[0]})

	local counter=0
	for dst_addr in "${dst_address_array[@]}"; do
		initial_dst_addr_balances[counter]=$(get_address_balance $dst_addr)

		if [ $?	!= 0 ]; then
			error_msg "Error when getting the balance of address: $dst_addr"
			exit 1
		fi

		counter=$(( counter + 1 ))
	done

	# set the tx_in_count based on input parameters and address balances
	total_transferred=$(awk 'BEGIN {t=0; for (i in ARGV) t+=ARGV[i]; print t}' "${amount_transferred_array[@]}")

	change=$(( highest_utxo_amount_balance - fee - total_transferred ))

	if (( change >= 0 )); then
		tx_in_count=1
		input_utxo=$(get_input_for_tx $highest_amount_utxo)
	else
		# If there are not enough funds into the UTXO with the highest amount but
		# If the address balance (all UTXOs) contains enough funds, use all UTXOs as input into the tx
		warn_msg "Not enough funds into the highest UTXO amout; change(utxo): $change"
		tx_in_count=$no_of_utxos
		change=$(( src_addr_balance - fee - total_transferred ))
		if (( change < 0 )); then
			error_msg "Not enough funds; change(address): $change"
			exit 1
		fi
		input_utxo="${utxo_array[@]}"
	fi

	echo "Sending ${amount_transferred_array[@]} LOVELACE from ${src_address_array[0]} to ${dst_address_array[@]}"
	info_msg "------------------------------------------------------------"
	info_msg "Current tip: $current_tip"
	info_msg "Tx ttl: $ttl"
	info_msg "Tx fee: $fee"
	info_msg "Source address: ${src_address_array[@]}"
	echo "Destination addresses: ${dst_address_array[@]}"
	echo "Amounts to be transferred: ${amount_transferred_array[@]} = $total_transferred"
	info_msg "No of source UTXOs: $no_of_utxos"
	info_msg "Highest source UTXO amount: $highest_amount_utxo"
	info_msg "Input UTXOs: $input_utxo"
	info_msg "Source address balance (before): $src_addr_balance"
	info_msg "Source address balance (after): $change"
	info_msg "------------------------------------------------------------"

	# Build TX
	info_msg "Building raw TX ..."

	if (( tx_in_count == 1 )); then
		tx_in_args[0]=$(echo "--tx-in $input_utxo ")
	else
		# Create the tx_in array with all the --tx-in parameters for the build-raw command
		local counter=0
		for utxo_string in "${utxo_array[@]}"; do
			tx_hash=$(echo $utxo_string | cut -d' ' -f1)
			tx_ix=$(echo $utxo_string | cut -d' ' -f2)
			tx_in_args[counter]=$(echo "--tx-in $tx_hash#$tx_ix ")
			counter=$(( counter + 1 ))
		done
	fi

	# Create the tx_out array with all the --tx-out parameters for the build-raw command
	local counter=0
	for dst_addr in "${dst_address_array[@]}"; do
		tx_out_args[counter]=$(echo "--tx-out ${dst_address_array[$counter]}+${amount_transferred_array[$counter]} ")
		counter=$(( counter + 1 ))
	done
	tx_out_args[counter]=$(echo "--tx-out ${src_address_array[0]}+${change} ")

	cardano-cli shelley transaction build-raw \
		--ttl $ttl \
		--fee $fee \
		${tx_in_args[@]} \
		${tx_out_args[@]} \
		--out-file $raw_tx_filepath

	# ISSUE with incorrect return code = 1 for success
	if [ $?	== 1 ]; then
		error_msg "Error when building raw transaction"
		exit 1
	fi

	# Sign TX
	info_msg "Signing TX ..."

	local counter=0
	for signing_key in "${signing_keys_array[@]}"; do
		signing_key_args[counter]=$(echo "--signing-key-file $signing_key ")
		counter=$(( counter + 1 ))
	done

	cardano-cli shelley transaction sign \
		${signing_key_args[@]} \
		--testnet-magic $testnet_magic \
		--tx-body-file $raw_tx_filepath \
		--out-file $signed_tx_filepath

	# ISSUE with incorrect return code = 1 for success
	if [ $?	== 1 ]; then
		error_msg "Error when signing transaction"
		exit 1
	fi

	# Submit TX
	info_msg "Submitting TX ..."

	cardano-cli shelley transaction submit \
		--tx-file "${signed_tx_filepath}" \
		--testnet-magic "${testnet_magic}"

	# ISSUE with incorrect return code = 1 for success
	if [ $?	== 1 ]; then
		error_msg "Error when submitting transaction"
		exit 1
	fi

	# Cleanup - remove the tmp_tx folder/files
	if [ -d $root_dirpath/tmp_txs ]; then
		rm -Rf $root_dirpath/tmp_txs
	fi

	# Wait for some time
	info_msg "Waiting for the tx to be included into a block ..."
	wait_for_new_tip
	# sometimes the address balances are not updated imediatelly after 1 new tip
	wait_for_new_tip

	# Check the balances
	info_msg "Checking the balance of the source address: ${src_address_array[0]}"
	$(assert_address_balance ${src_address_array[0]} $(( src_addr_balance - fee - total_transferred )))

	if [ $?	!= 0 ]; then
		error_msg "Error when asserting the balance of the source address"
		exit 1
	fi

	local counter=0
	for dst_addr in "${dst_address_array[@]}"; do
		info_msg "Checking the balance for destination address: $dst_addr"
		$(assert_address_balance $dst_addr $(( ${initial_dst_addr_balances[$counter]} + ${amount_transferred_array[$counter]})))

		if [ $?	!= 0 ]; then
			error_msg "Error when asserting the balance of the destination address: $dst_addr"
			exit 1
		fi

		counter=$(( counter + 1 ))
	done
}

# Sends funds from 1 payment address to 1 payment address
# Expects 4 input params:
# 1) source address - source address
# 2) destination address - destination address
# 3) amount transferred - amount [LOVELACE or ALL] to be transfered from source_address to destination_addresses
# 3.1) if amount_transferred = ALL, it will send all the funds (minus tx_fees) from source address to destination address
# 3.2) if there are not enough funds in the UTXO with the highest amount (of the source address), but there are enough funds
# into the address, all the UTXOs of the source address will be used into the trasaction
# 4) signing key - signing key of the source address

send_funds_one_dst () {
    _check_number_of_arguments 4 '1) source address' '2) destination address' '3) amount transferred' '4) signing key'

	# creating tmp_tx folder to keep the tx files until they are submitted
	if [ -d $root_dirpath/tmp_txs ]; then
		rm -Rf $root_dirpath/tmp_txs
	else
		mkdir $root_dirpath/tmp_txs
	fi

	raw_tx_filepath=$root_dirpath/tmp_txs/tx-body.raw
	signed_tx_filepath=$root_dirpath/tmp_txs/tx-body.signed

	local src_address=$1
	local dst_address=$2
	local amount_transferred=$3
	local signing_key=$4
	local tx_in_count=1
	local tx_out_count=2

	# Determine TTL
	current_tip=$(get_current_tip)

	if [ $? != 0 ]; then
		error_msg "Error when getting current tip"
		exit 1
	fi

	ttl=$(calculate_ttl)

	# Get current protocol params and write it to file
	$(get_protocol_params)

	if [ $?	!= 0 ]; then
		error_msg "Error when obtaining protocol parameters"
		exit 1
	fi

	# Get the number of UTXOs available in the source address
	no_of_utxos=$(get_no_of_utxos_for_address $src_address)

	if [ $? != 0 ]; then
		error_msg "Error while getting the number of UTXOs for address: $src_address"
		exit 1
	fi

	# Calculate fee
	if [ $amount_transferred == "ALL" ]; then
		tx_out_count=1
	fi

	fee=$(cardano-cli shelley transaction calculate-min-fee \
		--tx-in-count 1 \
		--tx-out-count $tx_out_count \
		--ttl $ttl \
		--testnet-magic $testnet_magic \
		--signing-key-file $signing_key \
		--protocol-params-file $protocol_params_filepath \
		| awk '{ print $2}')

	if [ $? != 0 ]; then
		error_msg "Error during fee calculation"
		exit 1
	fi

	# Get UTXOs from source address (to be used into the actual transaction)
	local src_utxos=$(get_utxos_for_address $src_address)
	local highest_amount_utxo=0
	local utxo_no=0
	local counter=0

	# Create an array with all the utxos from the source address
	readarray -t utxo_array <<<"$src_utxos"

	# Get the value and array_index of the UTXO with the highest amount of LOVELACE
	for utxo_string in "${utxo_array[@]}"; do
		utxo_amount=$(echo $utxo_string | cut -d' ' -f3)
		if (( utxo_amount >= highest_amount_utxo )); then
			highest_amount_utxo=$utxo_amount
			utxo_no=$counter
		fi
		counter=$(( counter + 1 ))
	done

	highest_amount_utxo=${utxo_array[$utxo_no]}
	highest_utxo_amount_balance=$(get_balance_for_tx $highest_amount_utxo)
	src_addr_balance=$(get_address_balance $src_address)
	dst_addr_balance=$(get_address_balance $dst_address)
	if [ $amount_transferred == "ALL" ]; then
		amount_transferred=$(( src_addr_balance - fee ))
	fi

	change=$(( highest_utxo_amount_balance - fee - amount_transferred ))

	# If there are not enough funds into the UTXO with the highest amount but
	# If the address balance (all UTXOs) contains enough funds, use all UTXOs as input into the tx
	if (( change < 0 )); then
		warn_msg "Not enough funds into the highest UTXO amout; change (utxo): $change"
		tx_in_count=$no_of_utxos
		fee=$(cardano-cli shelley transaction calculate-min-fee \
			--tx-in-count $tx_in_count \
			--tx-out-count $tx_out_count \
			--ttl $ttl \
			--testnet-magic $testnet_magic \
			--signing-key-file $signing_key \
			--protocol-params-file $protocol_params_filepath \
			| awk '{ print $2}')
		change=$(( src_addr_balance - fee - amount_transferred ))
		if (( change < 0 )); then
			error_msg "Not enough funds; change (address): $change"
			exit 1
		fi
	fi

	if (( tx_in_count == 1 )); then
		input_utxo=$(get_input_for_tx $highest_amount_utxo)
	else
		input_utxo="${utxo_array[@]}"
	fi

	info_msg "Sending $amount_transferred LOVELACE from $src_address to $dst_address"
	info_msg "------------------------------------------------------------"
	info_msg "Current tip: $current_tip"
	info_msg "Tx ttl: $ttl"
	info_msg "Source address: $src_address"
	info_msg "Destination address: $dst_address"
	info_msg "No of source UTXOs: $no_of_utxos"
	info_msg "Highest source UTXO amount: $highest_amount_utxo"
	info_msg "Input UTXO: $input_utxo"
	info_msg "Destination address balance (before): $dst_addr_balance"
	info_msg "Source address balance (before): $src_addr_balance"
	info_msg "Source address selected UTXO balance (before): $highest_utxo_amount_balance"
	info_msg "Amount trasfered: $amount_transferred"
	info_msg "Tx fee: $fee"
	info_msg "Source address balance (after): $change"
	info_msg "------------------------------------------------------------"

	# Build TX
	info_msg "Building raw TX ..."
	if (( tx_in_count == 1 )); then
		if [ $amount_transferred == "ALL" ]; then
			cardano-cli shelley transaction build-raw \
				--ttl $ttl \
				--fee $fee \
				--tx-in $input_utxo \
				--tx-out "${dst_address}+${amount_transferred}" \
				--out-file $raw_tx_filepath
		else
			cardano-cli shelley transaction build-raw \
				--ttl $ttl \
				--fee $fee \
				--tx-in $input_utxo \
				--tx-out "${dst_address}+${amount_transferred}" \
				--tx-out "${src_address}+${change}" \
				--out-file $raw_tx_filepath
		fi
	else
		if [ $amount_transferred == "ALL" ]; then
			local counter=0
			# Create the tx_in array with all the --tx-in parameters for the build-raw command
			for utxo_string in "${utxo_array[@]}"; do
				tx_hash=$(echo $utxo_string | cut -d' ' -f1)
				tx_ix=$(echo $utxo_string | cut -d' ' -f2)
				tx_in[counter]=$(echo "--tx-in $tx_hash#$tx_ix ")
				counter=$(( counter + 1 ))
			done
			cardano-cli shelley transaction build-raw \
				--ttl $ttl \
				--fee $fee \
				${tx_in[@]} \
				--tx-out "${dst_address}+${amount_transferred}" \
				--out-file $raw_tx_filepath
		else
			local counter=0
			# Create the tx_in array with all the --tx-in parameters for the build-raw command
			for utxo_string in "${utxo_array[@]}"; do
				tx_hash=$(echo $utxo_string | cut -d' ' -f1)
				tx_ix=$(echo $utxo_string | cut -d' ' -f2)
				tx_in[counter]=$(echo "--tx-in $tx_hash#$tx_ix ")
				counter=$(( counter + 1 ))
			done
			cardano-cli shelley transaction build-raw \
				--ttl $ttl \
				--fee $fee \
				${tx_in[@]} \
				--tx-out "${dst_address}+${amount_transferred}" \
				--tx-out "${src_address}+${change}" \
				--out-file $raw_tx_filepath
		fi
	fi

	# ISSUE with incorrect return code = 1 for success
	if [ $?	== 1 ]; then
		error_msg "Error when building raw transaction"
		exit 1
	fi

	# Sign TX
	info_msg "Signing TX ..."

	cardano-cli shelley transaction sign \
		--signing-key-file $signing_key \
		--testnet-magic $testnet_magic \
		--tx-body-file $raw_tx_filepath \
		--out-file $signed_tx_filepath

	# ISSUE with incorrect return code = 1 for success
	if [ $?	== 1 ]; then
		error_msg "Error when signing transaction"
		exit 1
	fi

	# Submit TX
	info_msg "Submitting TX ..."

	cardano-cli shelley transaction submit \
		--tx-file "${signed_tx_filepath}" \
		--testnet-magic "${testnet_magic}"

	# ISSUE with incorrect return code = 1 for success
	if [ $?	== 1 ]; then
		error_msg "Error when submitting transaction"
		exit 1
	fi

	# Cleanup - remove the tmp_tx folder/files
	if [ -d $root_dirpath/tmp_txs ]; then
		rm -Rf $root_dirpath/tmp_txs
	fi

	# Wait for some time
	info_msg "Waiting for the tx to be included into a block ..."
	wait_for_new_tip
	# sometimes the address balances are not updated imediatelly after 1 new tip
	wait_for_new_tip

	# Check the balances
	info_msg "Checking the balance of the destination address..."

	$(assert_address_balance $dst_address $(( dst_addr_balance + amount_transferred)))

	if [ $?	!= 0 ]; then
		error_msg "Error when asserting the balance of the destination address"
		exit 1
	fi

	info_msg "Checking the balance of the source address..."

	$(assert_address_balance $src_address $(( src_addr_balance - fee - amount_transferred )))

	if [ $?	!= 0 ]; then
		error_msg "Error when asserting the balance of the source address"
		exit 1
	fi
}

# Expects 1 input param:
# 1) user name - string in format: user+number (EX: user11, user112, etc)
# returns the number (EX: for user122, returns 112)

get_user_number () {
    _check_number_of_arguments 1 '1) user name'

    local user_name=$1
	echo $user_name | sed 's/[^0-9]*//g'
}

exec "$@"
