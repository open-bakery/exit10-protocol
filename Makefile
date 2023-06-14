# include .env file and export its env vars
# (-include to ignore error if it does not exist)
SHELL := /bin/bash
-include .env
DEPLOYMENT = local
DEPLOYMENT_FLIP = "local-flip"
ANVIL_PORT = 8545
ANVIL_PORT_FLIP = 8546
CHAIN_ID = 31337
CHAIN_ID_FLIP = 31338

reinit:
	git submodule deinit --force .
	git submodule update --init --recursive

#SED_REPLACE="s/{{WETH}}/$$WETH/;s/{{USDC}}/$$USDC/;s/{{UNISWAP_V3_FACTORY}}/$$UNISWAP_V3_FACTORY/;s/{{UNISWAP_V3_ROUTER}}/$$UNISWAP_V3_ROUTER/;s/{{UNISWAP_V3_NPM}}/$$UNISWAP_V3_NPM/;s/{{SWAPPER}}/$$SWAPPER/;s/{{UNISWAP_V2_ROUTER}}/$$UNISWAP_V2_ROUTER/;s/{{UNISWAP_V2_FACTORY}}/$$UNISWAP_V2_FACTORY/;s/{{POOL}}/$$POOL/"

kill-anvil:
	@if pidof anvil > /dev/null 2>&1; then \
		echo "Anvil is already running, killing it..."; \
		kill $$(pidof anvil); \
	fi

wait-for-anvil:
	@echo "Waiting for anvil to be online...";
	@while ! curl -s http://127.0.0.1:$(ANVIL_PORT) > /dev/null; do sleep 1; done
	@echo "Anvil online and outputting to anvil-$(ANVIL_PORT).log";

start-anvil-local:
	@echo "Starting anvil on port $(ANVIL_PORT)...";
	$(MAKE) kill-anvil
	@anvil --port $(ANVIL_PORT) --chain-id $(CHAIN_ID) --balance 1000000 > "anvil-$(ANVIL_PORT).log" &
	$(MAKE) wait-for-anvil

start-anvil-mainnet-fork:
	@echo "Starting anvil mainnet fork...";
	$(MAKE) kill-anvil
	@anvil --fork-url $(FORK_URL)
	$(MAKE) wait-for-anvil

merge-config:
	@#cat ./config/common.ini ./config/infrastructure/$(DEPLOYMENT).ini ./config/deployment/$(DEPLOYMENT).ini .env.secret > .env
	@awk 'FNR==1{print ""}{print}' ./config/common.ini ./config/$(DEPLOYMENT)/infrastructure.ini ./config/$(DEPLOYMENT)/deployment.ini .env.secret > .env

dev:
	@echo "RUN dev deployment=$(DEPLOYMENT), anvil_port=$(ANVIL_PORT)"
	#trap "kill $(jobs -p)" SIGINT SIGTERM EXIT
	$(MAKE) start-anvil-local
	@ETH_RPC_URL="http://localhost:$(ANVIL_PORT)" DEPLOYMENT=$(DEPLOYMENT) ./deploy/deploy-infrastructure.sh
	$(MAKE) merge-config

dev-flip:
	$(MAKE) dev DEPLOYMENT=$(DEPLOYMENT_FLIP) ANVIL_PORT=$(ANVIL_PORT_FLIP)

dev-twochain:
	$(MAKE) dev
	$(MAKE) dev-flip


dev-mainnet-fork:
	#trap "kill $(jobs -p)" SIGINT SIGTERM EXIT
	$(MAKE) start-anvil-mainnet-fork
	$(MAKE) deploy-infrastructure
	$(MAKE) merge-config

dev-ui:
	@echo "RUN dev-ui $(DEPLOYMENT)"
	$(MAKE) dev
	@ETH_RPC_URL=$(ETH_RPC_URL) DEPLOYMENT=$(DEPLOYMENT) ./deploy/deploy-exit10.sh
	@ETH_RPC_URL=$(ETH_RPC_URL) DEPLOYMENT=$(DEPLOYMENT) ./deploy/deploy-setup.sh
	@ETH_RPC_URL=$(ETH_RPC_URL) DEPLOYMENT=$(DEPLOYMENT) ./deploy/deploy-dev-data.sh
	DEPLOYMENT=$(DEPLOYMENT) ./deploy/export-to-ui.sh
	DEPLOYMENT=$(DEPLOYMENT) ./deploy/export-to-subgraph.sh

dev-ui-flip:
	$(MAKE) dev-ui DEPLOYMENT="local-flip" ANVIL_PORT="8546" CHAIN_ID="31338"

dev-ui-twochain:
	$(MAKE) dev-ui
	$(MAKE) dev-ui-flip

deploy-test:
	@DEPLOYMENT=$(DEPLOYMENT) ./deploy/deploy-test.sh

deploy-it:
	@echo "Deploying on '$(DEPLOYMENT)'"
	@DEPLOYMENT=$(DEPLOYMENT) ./deploy/deploy-exit10.sh

set-it-up:
	@DEPLOYMENT=$(DEPLOYMENT) ./deploy/deploy-setup.sh

gas-report:
	forge test -vv --nmc "SystemLogsTest|FuzzTest" --gas-report --fork-url $(ETH_RPC_URL)

testAll:
	forge test -vv --fork-url $(ETH_RPC_URL)

tests:
	forge test -vv  --nmc "SystemLogsTest|FuzzTest|NFT_Test" --fork-url $(ETH_RPC_URL)

trace:
	forge test -vv --nmc "SystemLogsTest|FuzzTest|NFT_Test" --fork-url $(ETH_RPC_URL)

single:
	forge test -vv --mt "testGenerateDecimalString" --fork-url $(RPC_URL)

systemLogs:
	forge test -vv --mc SystemLogsTest --fork-url $(ETH_RPC_URL)

fuzz:
	forge test -vv --mc FuzzTest --fork-url $(ETH_RPC_URL)

param:
	@echo $$param
	@source ./config/param1.ini && echo $$PARAM1
	./some-script.sh