all          :; DAPP_BUILD_OPTIMIZE=1 DAPP_BUILD_OPTIMIZE_RUNS=200 forge build --use solc:0.8.14
clean        :; dapp clean
test         :; make && ./test.sh $(match)
certora-base :; $(if $(CERTORAKEY),, @echo "set certora key"; exit 1;) PATH=~/.solc-select/artifacts/:${PATH} certoraRun ./.certora.conf
