#!/bin/bash

echo "======================== submit-initial-blockchain-transaction.sh ========================" 2>&1 | tee -a output.log

sleep 30

echo "Submitting first transaction ever to transfer all funds from intial UTXO to addr1" 2>&1 | tee -a output.log
export CARDANO_NODE_SOCKET_PATH=example/node-bft1/node.sock
$(cardano-cli shelley transaction submit --tx-file example/tx1.tx --testnet-magic 42 2>&1 | tee -a output.log)

if [ $?	== 1 ]; then
    echo "Error when submitting transaction"
    exit 1
fi

# Wait a bit afee submission
sleep 3

# Select some fee that will satisfy conditions
fee=3000000
tx=$(cardano-cli shelley query utxo --testnet-magic 42 --address $(cat example/addresses/user1.addr) | grep "^[^- ]" | sort -k 2n | tail -1)
utxo=$(echo $tx | awk -F' ' '{print $1}')
id=$(echo $tx | awk -F' ' '{print $2}')
balance=$(echo $tx | awk -F' ' '{print $3}')
change=$(( balance - fee - 800000 - 5000000))
input="${utxo}#${id}"


echo "Creating second transaction in order to register all certificates and stake pool" 2>&1 | tee -a output.log
echo "TX input: $input" 2>&1 | tee -a output.log
echo "TX balance: $balance" 2>&1 | tee -a output.log
echo "TX change: $change" 2>&1 | tee -a output.log

cardano-cli shelley transaction build-raw \
    --ttl 10000 \
    --fee $fee \
    --tx-in $input \
    --tx-out "$(cat example/addresses/user1.addr)+${change}" \
    --certificate-file example/addresses/pool-owner1-stake.reg.cert \
    --certificate-file example/node-pool1/registration.cert \
    --certificate-file example/addresses/user1-stake.reg.cert \
    --certificate-file example/addresses/user1-stake.deleg.cert \
    --out-file example/tx2.txbody

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
   --signing-key-file example/addresses/user1.skey \
   --signing-key-file example/utxo-keys/utxo1.skey \
   --signing-key-file example/addresses/user1-stake.skey \
   --signing-key-file example/node-pool1/owner.skey \
   --signing-key-file example/node-pool1/operator.skey \
   --testnet-magic 42 \
   --tx-body-file  example/tx2.txbody \
   --out-file      example/tx2.tx

if [ $?	== 1 ]; then
    echo "Error when signing transaction"
    exit 1
fi

echo "Submitting second transaction to register stake address 1 and stake pool 1" 2>&1 | tee -a output.log

cardano-cli shelley transaction submit --tx-file example/tx2.tx --testnet-magic 42 2>&1 | tee -a output.log

if [ $?	== 1 ]; then
    echo "Error when submitting transaction"
    exit 1
fi
