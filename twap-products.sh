#!/bin/bash
# usage example: ./twap-products.sh 15740914 100

END=$1
BACK=$2

start=$[$END-$BACK]

for (( b=$start; b<=$END; b++ ))
do
   forge test --use solc:0.8.14 --rpc-url "$ETH_RPC_URL" --match testStat -vvv --fork-block-number $b | grep Debug
done

