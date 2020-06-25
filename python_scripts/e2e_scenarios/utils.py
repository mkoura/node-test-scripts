import re
import shutil
import subprocess
import os
from time import sleep

from e2e_scenarios.constants import TESTNET_MAGIC, PROTOCOL_PARAMS_FILEPATH, NODE_SOCKET_PATH


def delete_folder(location_offline_tx_folder):
    print(f"=================== Removing the {location_offline_tx_folder} folder...")
    if os.path.exists(location_offline_tx_folder) and os.path.isdir(location_offline_tx_folder):
        try:
            shutil.rmtree(location_offline_tx_folder)
        except OSError as e:
            print("!!! Error: %s - %s." % (e.filename, e.strerror))
    else:
        print(f"Folder does not exists - {location_offline_tx_folder}")


def set_node_socket_path_env_var():
    os.environ['CARDANO_NODE_SOCKET_PATH'] = NODE_SOCKET_PATH


def create_payment_key_pair(location, key_name):
    try:
        cmd = "cardano-cli shelley address key-gen --verification-key-file " \
              + location + "/" + key_name \
              + ".vkey --signing-key-file " \
              + location + "/" + key_name + ".skey"
        return subprocess.check_output(cmd, shell=True, stderr=subprocess.STDOUT).decode("utf-8").strip()
    except subprocess.CalledProcessError as e:
        raise RuntimeError("command '{}' return with error (code {}): {}".format(e.cmd, e.returncode, e.output))


def build_payment_address(location, addr_name):
    try:
        cmd = "cardano-cli shelley address build" \
              " --payment-verification-key-file " + location + "/" + addr_name + ".vkey" + \
              " --testnet-magic " + TESTNET_MAGIC + \
              " --out-file " + location + "/" + addr_name + ".addr"
        return subprocess.check_output(cmd, shell=True, stderr=subprocess.STDOUT).decode("utf-8").strip()
    except subprocess.CalledProcessError as e:
        raise RuntimeError("command '{}' return with error (code {}): {}".format(e.cmd, e.returncode, e.output))


def create_payment_key_pair_and_address(location, addr_name):
    create_payment_key_pair(location, addr_name)
    build_payment_address(location, addr_name)


def read_address_from_file(location, address_file_name):
    with open(location + "/" + address_file_name + ".addr", 'r') as file:
        address = file.read().replace('\n', '')
    return address


def get_protocol_params():
    set_node_socket_path_env_var()
    try:
        cmd = "cardano-cli shelley query protocol-parameters" \
              " --testnet-magic " + TESTNET_MAGIC + \
              " --out-file " + PROTOCOL_PARAMS_FILEPATH
        return subprocess.check_output(cmd, shell=True, stderr=subprocess.STDOUT).decode("utf-8").strip()
    except subprocess.CalledProcessError as e:
        raise RuntimeError("command '{}' return with error (code {}): {}".format(e.cmd, e.returncode, e.output))


def get_current_tip():
    set_node_socket_path_env_var()
    try:
        cmd = "cardano-cli shelley query tip --testnet-magic " + TESTNET_MAGIC
        result = subprocess.check_output(cmd, shell=True, stderr=subprocess.STDOUT).decode("utf-8").strip()
        return int(re.findall(r'%s(\d+)' % 'unSlotNo = ', result)[0])
    except subprocess.CalledProcessError as e:
        raise RuntimeError("command '{}' return with error (code {}): {}".format(e.cmd, e.returncode, e.output))


def get_address_utxos(address):
    # this will create a list of utxos in this format: ['utxo_hash', utxo_ix, utxo_amount]
    set_node_socket_path_env_var()
    available_utxos_list = []
    try:
        cmd = "cardano-cli shelley query utxo" \
              " --testnet-magic " + TESTNET_MAGIC + \
              " --address " + address + " | grep '^[^- ]'"
        address_utxo_list = subprocess.check_output(cmd, shell=True, stderr=subprocess.STDOUT).decode(
            "utf-8").strip().splitlines()

        for utxo in address_utxo_list:
            formatted_utxo = re.split("[\s,]+", utxo)
            utxo_hash = formatted_utxo[0]
            utxo_ix = int(formatted_utxo[1])
            utxo_amount = int(formatted_utxo[2])
            available_utxos_list.append([utxo_hash, utxo_ix, utxo_amount])
        return available_utxos_list
    except subprocess.CalledProcessError as e:
        raise RuntimeError("command '{}' return with error (code {}): {}".format(e.cmd, e.returncode, e.output))


def get_address_balance(address):
    address_balance = 0
    available_utxos_list = get_address_utxos(address)
    for utxo in available_utxos_list:
        utxo_amount = utxo[2]
        address_balance += utxo_amount
    return address_balance


def assert_address_balance(address, expected_balance):
    actual_balance = get_address_balance(address)
    if actual_balance != expected_balance:
        print(f"ERROR: Incorrect amount of funds for address. Actual: {actual_balance}  vs  Expected: {expected_balance}")
        exit(2)
    else:
        print(f"Success: Correct balance: {expected_balance} for address {address}")


def get_no_of_utxos_for_address(address):
    available_utxos_list = get_address_utxos(address)
    return len(available_utxos_list)


def get_utxo_with_highest_value(address):
    # this will return the utxo in this format: ('utxo_hash', utxo_ix, utxo_amount)
    utxo_hash_highest_amount = ""
    utxo_ix_highest_amount = ""
    highest_amount = 0
    available_utxos_list = get_address_utxos(address)
    for utxo in available_utxos_list:
        utxo_amount = utxo[2]
        if utxo_amount > highest_amount:
            highest_amount = utxo_amount
            utxo_hash_highest_amount = utxo[0]
            utxo_ix_highest_amount = utxo[1]
    return [utxo_hash_highest_amount, utxo_ix_highest_amount, highest_amount]


def calculate_tx_ttl():
    current_tip = get_current_tip()
    return current_tip + 1000


def calculate_tx_fee(tx_in_count, tx_out_count, ttl, **options):
    # **options can be: signing_keys, certificates, withdrawal, has-metadata
    get_protocol_params()
    cmd = "cardano-cli shelley transaction calculate-min-fee" \
          " --testnet-magic " + TESTNET_MAGIC + \
          " --tx-in-count " + str(tx_in_count) + \
          " --tx-out-count " + str(tx_out_count) + \
          " --ttl " + str(ttl) + \
          " --protocol-params-file " + PROTOCOL_PARAMS_FILEPATH
    try:
        if options.get("signing_keys"):
            signing_keys = options.get('signing_keys')
            signing_keys_cmd = ''.join([" --signing-key-file " + key for key in signing_keys])
            cmd = cmd + signing_keys_cmd
        if options.get("certificates"):
            certificates = options.get('certificates')
            certificates_cmd = ''.join([" --certificate " + cert for cert in certificates])
            cmd = cmd + certificates_cmd
        result = subprocess.check_output(cmd, shell=True, stderr=subprocess.STDOUT).decode("utf-8").strip()
        return int(result.split(': ')[1])
    except subprocess.CalledProcessError as e:
        raise RuntimeError("command '{}' return with error (code {}): {}".format(e.cmd, e.returncode, e.output))


def get_slot_length():
    # TO DO: take this value from genesis; first define where genesis will be located
    slot_length = 1
    return slot_length


def wait_for_new_tip():
    print ("Waiting for a new block to be created")
    slot_length = get_slot_length()
    timeout_no_of_slots = 200
    current_tip = get_current_tip()
    initial_tip = get_current_tip()
    print(f"initial_tip: {initial_tip}")
    while current_tip == initial_tip:
        sleep(slot_length)
        current_tip = get_current_tip()
        timeout_no_of_slots -= 1
        if timeout_no_of_slots < 2:
            print(f"ERROR: Waited for {timeout_no_of_slots} slots but no new block was created")
            exit(2)
    print(f"New block was created; slot number: {current_tip}")


def build_raw_transaction(ttl, fee, **options):
    # **options can be: tx_in, tx_out, certificates, withdrawal, metadata-file, update-proposal-file
    # tx_in = list of input utxos in this format: (utxo_hash#utxo_ix)
    # tx_out = list of outputs in this format: (address+amount)

    out_file = "tx_raw.body"

    cmd = "cardano-cli shelley transaction build-raw" \
          " --fee " + str(fee) + \
          " --ttl " + str(ttl) + \
          " --out-file " + out_file
    try:
        if options.get("tx_in"):
            tx_in = options.get('tx_in')
            tx_in_cmd = ''.join([" --tx-in " + tx_in_el for tx_in_el in tx_in])
            cmd = cmd + tx_in_cmd

        if options.get("tx_out"):
            tx_out = options.get('tx_out')
            tx_out_cmd = ''.join([" --tx-out " + tx_out_el for tx_out_el in tx_out])
            cmd = cmd + tx_out_cmd

        subprocess.check_output(cmd, shell=True, stderr=subprocess.STDOUT).decode("utf-8").strip()
        return out_file
    except subprocess.CalledProcessError as e:
        raise RuntimeError("command '{}' return with error (code {}): {}".format(e.cmd, e.returncode, e.output))


def sign_raw_transaction(tx_body_file, **options):
    # **options can be: signing_keys
    # signing_keys = list of file paths for the signing keys

    out_file = "tx_raw.signed"

    cmd = "cardano-cli shelley transaction sign" \
          " --testnet-magic " + TESTNET_MAGIC + \
          " --tx-body-file " + tx_body_file + \
          " --out-file " + out_file
    try:
        if options.get("signing_keys"):
            signing_keys_list = options.get('signing_keys')
            signing_key_cmd = ''.join([" --signing-key-file " + signing_key for signing_key in signing_keys_list])
            cmd = cmd + signing_key_cmd

        subprocess.check_output(cmd, shell=True, stderr=subprocess.STDOUT).decode("utf-8").strip()
        return out_file
    except subprocess.CalledProcessError as e:
        raise RuntimeError("command '{}' return with error (code {}): {}".format(e.cmd, e.returncode, e.output))


def submit_raw_transaction(tx_file):
    try:
        cmd = "cardano-cli shelley transaction submit" \
              " --testnet-magic " + TESTNET_MAGIC + \
              " --tx-file " + tx_file
        result = subprocess.check_output(cmd, shell=True, stderr=subprocess.STDOUT).decode("utf-8").strip()
        return result
    except subprocess.CalledProcessError as e:
        raise RuntimeError("command '{}' return with error (code {}): {}".format(e.cmd, e.returncode, e.output))


def send_funds(src_address, tx_fee, tx_ttl, **options):
    # **options can be: transferred_amounts, destinations_list, signing_keys
    global input_utxos_list, transferred_amounts, signing_keys_list
    required_funds, change = 0, 0

    # get the balance of the source address
    src_addr_balance = get_address_balance(src_address)

    # get the highest amount utxo included into the source address
    src_addr_highest_utxo_details = get_utxo_with_highest_value(src_address)
    src_addr_highest_utxo_amount = src_addr_highest_utxo_details[2]

    # calculate the required funds for transaction (=sum(dest_addresses) + tx_fee)
    if options.get("transferred_amounts"):
        if not options.get("destinations_list"):
            print("ERROR: 'transferred_amounts' option was provided but 'destinations_list' option was not provided.")
            exit(2)

        destinations_list = options.get('destinations_list')
        transferred_amounts = options.get('transferred_amounts')

        if len(destinations_list) != len(transferred_amounts):
            print(f"ERROR: len('transferred_amounts') {len(destinations_list)} != len('destinations_list') {len(destinations_list)}")
            exit(2)
        required_funds = sum(transferred_amounts) + tx_fee
    else:
        required_funds = tx_fee

    # create the list of transaction inputs
    input_utxos_list_for_tx = []
    if src_addr_highest_utxo_amount >= required_funds:
        input_utxo = src_addr_highest_utxo_details
        change = src_addr_highest_utxo_amount - required_funds
        input_utxos_list_for_tx.append(str(input_utxo[0]) + "#" + str(input_utxo[1]))
    elif src_addr_balance >= required_funds:
        input_utxos_list = get_address_utxos(src_address)
        for utxo in input_utxos_list:
            input_utxos_list_for_tx.append(str(utxo[0]) + "#" + str(utxo[1]))
        change = src_addr_balance - required_funds
    else:
        print(
            f"ERROR: Not enough funds; Required: {required_funds}  vs  Available: {src_addr_balance}; Change: {change}")
        exit(2)

    # create the list of transaction outputs
    out_change_list = []
    if options.get("destinations_list"):
        destinations_list = options.get('destinations_list')
        for dst, dst_amount in zip(destinations_list, transferred_amounts):
            out_change_list.append(dst + "+" + str(dst_amount))
        if change > 0:
            out_change_list.append(src_address + "+" + str(change))
    else:
        out_change_list.append(src_address + "+" + str(change))

    # create the list of transaction signing keys
    if options.get("signing_keys"):
        signing_keys_list = options.get('signing_keys')

    print(f"required_funds: {required_funds}")
    print(f"change: {change}")
    print(f"src_addr_highest_utxo_amount: {src_addr_highest_utxo_amount}")
    print(f"src_addr_balance: {src_addr_balance}")

    tx_body_file = build_raw_transaction(tx_ttl, tx_fee, tx_in=input_utxos_list_for_tx, tx_out=out_change_list)
    tx_signed_file = sign_raw_transaction(tx_body_file, signing_keys=signing_keys_list)
    submit_raw_transaction(tx_signed_file)

