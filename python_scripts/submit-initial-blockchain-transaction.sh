#!/bin/bash

testnet_magic=42
pool_deposit=5000000
key_deposit=400000

root=e2e-tests-directory
output_log_filename=output.log
output_log_filepath=$root/$output_log_filename

addresses_dir_path=$root/addresses
user1_payment_address_filename=user1.addr
user1_payment_address_filepath=$addresses_dir_path/$user1_payment_address_filename

pool1_dirpath=$root/node-pool1
utxo_keys_dirpath=$root/utxo-keys

init_blockchain_txs_dir_name=$root/init_blockchain_txs

echo "======================== submit-initial-blockchain-transaction.sh ========================" 2>&1 | tee -a $output_log_filepath

sleep 30

echo "Submitting first transaction ever to transfer all funds from intial UTXO to addr1" 2>&1 | tee -a $output_log_filepath
export CARDANO_NODE_SOCKET_PATH=$root/node-bft1/node.sock
$(cardano-cli shelley transaction submit --tx-file $init_blockchain_txs_dir_name/tx1.tx --testnet-magic $testnet_magic 2>&1 | tee -a $output_log_filepath)

if [ $?	== 1 ]; then
    echo "Error when submitting transaction"
    exit 1
fi

# Wait a bit afee submission
sleep 3

echo "Submitting first transaction was successful" 2>&1 | tee -a $output_log_filepath

# Select some fee that will satisfy conditions
fee=3000000
tx=$(cardano-cli shelley query utxo --testnet-magic $testnet_magic --address $(cat $user1_payment_address_filepath) | grep "^[^- ]" | sort -k 2n | tail -1)
utxo=$(echo $tx | awk -F' ' '{print $1}')
id=$(echo $tx | awk -F' ' '{print $2}')
balance=$(echo $tx | awk -F' ' '{print $3}')
change=$(( balance - fee - (2 * $key_deposit) - $pool_deposit))
input="${utxo}#${id}"


echo "Creating second transaction in order to register all certificates and stake pool" 2>&1 | tee -a $output_log_filepath
echo "TX input: $input" 2>&1 | tee -a $output_log_filepath
echo "TX balance: $balance" 2>&1 | tee -a $output_log_filepath
echo "TX change: $change" 2>&1 | tee -a $output_log_filepath

cardano-cli shelley transaction build-raw \
    --ttl 10000 \
    --fee $fee \
    --tx-in $input \
    --tx-out "$(cat $user1_payment_address_filepath)+${change}" \
    --certificate-file $addresses_dir_path/pool-owner1-stake.reg.cert \
    --certificate-file $pool1_dirpath/registration.cert \
    --certificate-file $addresses_dir_path/user1-stake.reg.cert \
    --certificate-file $addresses_dir_path/user1-stake.deleg.cert \
    --out-file $init_blockchain_txs_dir_name/tx2.txbody

if [ $?	== 1 ]; then
    echo "Error when building raw transaction"
    exit 1
fi

# We'll need to sign this with a bunch of keys:
# 1. the initial utxo spending key, for the funds
# 2. the user1 stake address key, due to the delegatation cert
# 3. the pool1 owner key, due to the pool registration cert
# 3. the pool1 operator key, due to the pool registration cert

cardano-cli shelley transaction sign \
   --signing-key-file $addresses_dir_path/user1.skey \
   --signing-key-file $utxo_keys_dirpath/utxo1.skey \
   --signing-key-file $addresses_dir_path/user1-stake.skey \
   --signing-key-file $pool1_dirpath/owner.skey \
   --signing-key-file $pool1_dirpath/operator.skey \
   --testnet-magic $testnet_magic \
   --tx-body-file  $init_blockchain_txs_dir_name/tx2.txbody \
   --out-file      $init_blockchain_txs_dir_name/tx2.tx

if [ $?	== 1 ]; then
    echo "Error when signing transaction"
    exit 1
fi

echo "Submitting second transaction to register stake address 1 and stake pool 1" 2>&1 | tee -a $output_log_filepath

cardano-cli shelley transaction submit --tx-file $init_blockchain_txs_dir_name/tx2.tx --testnet-magic $testnet_magic 2>&1 | tee -a $output_log_filepath

if [ $?	== 1 ]; then
    echo "Error when submitting transaction"
    exit 1
fi

echo "Submitting second transaction was successful" 2>&1 | tee -a $output_log_filepath
