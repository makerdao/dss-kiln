all          :; DAPP_BUILD_OPTIMIZE=1 DAPP_BUILD_OPTIMIZE_RUNS=200 forge build --use solc:0.8.14
clean        :; dapp clean
test         :; make && ./test.sh $(match)
certora-base :; $(if $(CERTORAKEY),, @echo "set certora key"; exit 1;) PATH=~/.solc-select/artifacts/solc-0.8.14:~/.solc-select/artifacts/solc-0.6.12:~/.solc-select/artifacts/solc-0.5.12:~/.solc-select/artifacts:${PATH} certoraRun --solc_map KilnMock=solc-0.8.14,Dai=solc-0.5.12,DSToken=solc-0.6.12,MockAuthority=solc-0.6.12,PoolMock=solc-0.6.12 --optimize_map KilnMock=200,Dai=0,DSToken=200,MockAuthority=0,PoolMock=0 certora/KilnMock.sol certora/Dai.sol certora/DSToken.sol certora/MockAuthority.sol certora/PoolMock.sol --link KilnMock:sell=Dai KilnMock:buy=DSToken PoolMock:dai=Dai PoolMock:token=DSToken KilnMock:pool=PoolMock DSToken:authority=MockAuthority --verify KilnMock:certora/KilnBase.spec --rule_sanity $(if $(rule),--rule $(rule),) --multi_assert_check --short_output
