all    :; DAPP_BUILD_OPTIMIZE=1 DAPP_BUILD_OPTIMIZE_RUNS=200 forge build --use solc:0.8.13
clean  :; dapp clean
test   :; make && ./test.sh $(match)
