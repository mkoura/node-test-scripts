import os, sys
import time
from pathlib import Path

dir_path = os.path.dirname(os.path.realpath(__file__))
parent_dir_path = os.path.abspath(os.path.join(dir_path, os.pardir))
sys.path.insert(0, parent_dir_path)

from e2e_scenarios.constants import USER1_ADDRESS, USER1_SKEY_FILE_PATH
from e2e_scenarios.utils import create_payment_key_pair_and_address, calculate_tx_fee, calculate_tx_ttl, \
    build_raw_transaction, get_utxo_with_highest_value, send_funds, read_address_from_file, get_address_balance, \
    wait_for_new_tip, assert_address_balance

# Scenario
# 1. Step1: create 2 new payment addresses (addr0, addr1)
# 2. Step2: send some funds form user1 (the faucet) to one of the addresses (addr0)
# 3. Step3: send ALL of the funds from addr0 to addr1
# 4. check that the balances of the 3 addresses were correctly updated

print("Creating a new folder for the files created by the current test...")
tmp_directory_for_script_files = "tmp_" + sys.argv[0].split(".")[0]
Path(tmp_directory_for_script_files).mkdir(parents=True, exist_ok=True)

no_of_addr_to_be_created = 2
print(f"=== Step1: Creating {no_of_addr_to_be_created} new payment key pair(s) and address(es)")
created_addresses_dict = {}
for count in range(0, no_of_addr_to_be_created):
    addr_name = "addr" + str(count)
    create_payment_key_pair_and_address(tmp_directory_for_script_files, addr_name)
    created_addresses_dict[addr_name] = read_address_from_file(tmp_directory_for_script_files, addr_name)

print(f"Addresses created for the current test: {created_addresses_dict}")

first_address_name = list(created_addresses_dict)[0]
print(f"first_address: {first_address_name}")

print(f"=== Step2: Send funds from user1 (faucet) to one of the newly created addresses")

src_address = USER1_ADDRESS
dst_addresses_list = [created_addresses_dict.get(first_address_name)]
transferred_amounts_list = [2000]
signing_keys_list = [USER1_SKEY_FILE_PATH]

print("Calculate the ttl for the funds transfer transaction")
tx_ttl = calculate_tx_ttl()

print("Calculate the tx fee for the funds transfer transaction")
tx_fee = calculate_tx_fee(1, len(dst_addresses_list) + 1, tx_ttl, signing_keys=[USER1_SKEY_FILE_PATH])

src_add_balance_init = get_address_balance(src_address)
src_add_balance_init = get_address_balance(src_address)
print(f"src_add_balance_init: {src_add_balance_init}")

print(f"Send {transferred_amounts_list} Lovelace from {src_address} to {dst_addresses_list}")
send_funds(src_address, tx_fee, tx_ttl,
           destinations_list=dst_addresses_list,
           transferred_amounts=transferred_amounts_list,
           signing_keys=signing_keys_list)

wait_for_new_tip()

print(f"Check that the balance for source address was correctly updated")
assert_address_balance(src_address, src_add_balance_init - tx_fee - sum(transferred_amounts_list))

