#!/bin/bash

export ETH_FROM=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
MAX_ALLOWANCE="0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"

SD="$(dirname "$(readlink -f "$0")")"
source "$SD/../.env";

function extract_contract_address() {
  cat < /dev/stdin | grep contractAddress | awk '{ print $2 }' | cut -c 3-43 | tr '[:upper:]' '[:lower:]'
}

DEC6="000000"
DEC18="000000000000000000"

# send tokens to alice
# alice doesn't want that much eth. makes the ui more difficult to work with. She'll have 100 WETH and 200 ETH
cast send --from "$ALICE_ADDRESS" --value "100$DEC18" "$WETH" "deposit()" > /dev/null
cast send --from "$DEPLOYER_ADDRESS" "$USDC" "transfer(address,uint256)" "$ALICE_ADDRESS" "500000$DEC6" > /dev/null
cast send --from "$ALICE_ADDRESS" --value "999700$DEC18"

# mint exit10 position in advance, not strictly necessary, might not do it in some scenarios
cast send --from "$ALICE_ADDRESS" "$WETH" "approve(address,uint256)" "$UNISWAP_V3_NPM" $MAX_ALLOWANCE > /dev/null
cast send --from "$ALICE_ADDRESS" "$USDC" "approve(address,uint256)" "$UNISWAP_V3_NPM" $MAX_ALLOWANCE > /dev/null
cast send --from "$ALICE_ADDRESS" "$UNISWAP_V3_NPM" "mint((address,address,uint24,int24,int24,uint256,uint256,uint256,uint256,address,uint256))(uint256,uint128,uint256,uint256)" "($USDC,$WETH,500,$LOWER_TICK,$UPPER_TICK,100000000000,500000000000000000000,0,0,$ALICE_ADDRESS,10000000000000000000000000000)" > /dev/null


