# include .env file and export its env vars
# (-include to ignore error if it does not exist)
SHELL := /bin/bash
-include .env

reinit:
	git submodule deinit --force .
	git submodule update --init --recursive

SED_REPLACE="s/{{WETH}}/$$WETH/;s/{{USDC}}/$$USDC/;s/{{UNISWAP_V3_FACTORY}}/$$UNISWAP_V3_FACTORY/;s/{{UNISWAP_V3_ROUTER}}/$$UNISWAP_V3_ROUTER/;s/{{UNISWAP_V3_NPM}}/$$UNISWAP_V3_NPM/;s/{{SWAPPER}}/$$SWAPPER/;s/{{UNISWAP_V2_ROUTER}}/$$UNISWAP_V2_ROUTER/;s/{{UNISWAP_V2_FACTORY}}/$$UNISWAP_V2_FACTORY/;s/{{POOL}}/$$POOL/"

kill-anvil:
	@if pidof anvil > /dev/null 2>&1; then \
		echo "Anvil is already running, killing it..."; \
		kill $$(pidof anvil); \
	fi

wait-for-anvil:
	@echo "Waiting for anvil to be online...";
	@while ! curl -s http://127.0.0.1:8545 > /dev/null; do sleep 1; done
	@echo "Anvil online and outputting to anvil.log";
	@echo 'Kill it with: kill $(pidof anvil)'

start-anvil-local:
	$(MAKE) kill-anvil
	@echo "Starting anvil...";
	@anvil --balance 1000000 > anvil.log &
	$(MAKE) wait-for-anvil

start-anvil-mainnet-fork:
	$(MAKE) kill-anvil
	@echo "Starting anvil mainnet fork...";
	@anvil --fork-url $(RPC_URL)
	$(MAKE) wait-for-anvil

deploy-infrastructure:
	@echo "Deploying infrastrucure locally..."
	@./deploy/deploy-infrastructure.sh
	@echo "Deployed!"

dev:
	#trap "kill $(jobs -p)" SIGINT SIGTERM EXIT
	$(MAKE) start-anvil-local
	$(MAKE) deploy-infrastructure
	@source ./config/local.ini ; sed < .env.template > .env $(SED_REPLACE)

dev-ui:
	$(MAKE) dev
	./deploy/deploy-exit10.sh
	./deploy/deploy-dev-data.sh
	./deploy/export-local-ini-to-ui.sh

dev-mainnet-fork:
	#trap "kill $(jobs -p)" SIGINT SIGTERM EXIT
	$(MAKE) start-anvil-mainnet-fork
	$(MAKE) deploy-infrastructure
	@source ./config/mainnet.ini ; sed < .env.template > .env $(SED_REPLACE)

gas-report:
	forge test -vv --mc Exit10 --gas-report --fork-url $(RPC_URL)

tests:
	forge test -vv  --nmc SystemTest --fork-url $(RPC_URL)

trace:
	forge test -vvv --mc DepositHelperTest --fork-url $(RPC_URL)

trace1:
	forge test -vvv --mt test_addLiquidityBypass --fork-url $(RPC_URL)

test1:
	forge test -vv --mc Exit10_convertBondTest --fork-url $(RPC_URL)

system:
	forge test -vv --mc SystemTest --fork-url $(RPC_URL)

fuzz:
	forge test --mc UnitTest --fork-url $(RPC_URL)

