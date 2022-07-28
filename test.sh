#!/usr/bin/env bash
set -e

[[ "$ETH_RPC_URL" && "$(cast chain)" == "ethlive" ]] || { echo "Please set a mainnet ETH_RPC_URL"; exit 1; }

export DAPP_BUILD_OPTIMIZE=1
export DAPP_BUILD_OPTIMIZE_RUNS=200

if [[ -z "$1" ]]; then
  forge test --use solc:0.8.14 --rpc-url="$ETH_RPC_URL" -vvv
else
  forge test --use solc:0.8.14 --rpc-url="$ETH_RPC_URL" --match "$1" -vvvv
fi
