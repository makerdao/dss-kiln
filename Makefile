all          :; DAPP_BUILD_OPTIMIZE=1 DAPP_BUILD_OPTIMIZE_RUNS=200 forge build --use solc:0.8.14
clean        :; dapp clean
test         :; make && ./test.sh $(match)
certora-base :; certoraRun --solc ~/.solc-select/artifacts/solc-0.8.14 ./certora/KilnMock.sol --verify KilnMock:certora/KilnBase.spec --solc_args "['--optimize','--optimize-runs','200']" --rule_sanity $(if $(rule),--rule $(rule),) --multi_assert_check --short_output
