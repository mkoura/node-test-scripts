cd ..

cardano-node run \
    --topology relay/ff-topology.json \
    --database-path relay/db \
    --socket-path relay/db/node.socket \
    --port 3002 \
    --config relay/ff-config.json > run-node-log.txt
