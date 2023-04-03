#!/bin/bash

export ETH_FROM=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
MAX_ALLOWANCE="0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
DEADLINE=16805241220

SD="$(dirname "$(readlink -f "$0")")"
source "$SD/../.env";
source "$SD/../config/local.ini";

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

# send usdc to everyone else
cast send --from "$DEPLOYER_ADDRESS" "$USDC" "transfer(address,uint256)" "$BOB_ADDRESS" "500000$DEC6" > /dev/null
cast send --from "$DEPLOYER_ADDRESS" "$USDC" "transfer(address,uint256)" "$CHARLIE_ADDRESS" "500000$DEC6" > /dev/null
cast send --from "$DEPLOYER_ADDRESS" "$USDC" "transfer(address,uint256)" "$DAVE_ADDRESS" "500000$DEC6" > /dev/null


# mint exit10 position in advance, not strictly necessary, might not do it in some scenarios
#cast send --from "$ALICE_ADDRESS" "$WETH" "approve(address,uint256)" "$UNISWAP_V3_NPM" $MAX_ALLOWANCE > /dev/null
#cast send --from "$ALICE_ADDRESS" "$USDC" "approve(address,uint256)" "$UNISWAP_V3_NPM" $MAX_ALLOWANCE > /dev/null
#cast send --from "$ALICE_ADDRESS" "$UNISWAP_V3_NPM" "mint((address,address,uint24,int24,int24,uint256,uint256,uint256,uint256,address,uint256))(uint256,uint128,uint256,uint256)" "($USDC,$WETH,500,$LOWER_TICK,$UPPER_TICK,100000000000,500000000000000000000,0,0,$ALICE_ADDRESS,10000000000000000000000000000)" > /dev/null

# alice approves usdc/weth so that she can skip that in the ui, other testing accounts won't
cast send --from "$ALICE_ADDRESS" "$WETH" "approve(address,uint256)" "$EXIT10" $MAX_ALLOWANCE > /dev/null
cast send --from "$ALICE_ADDRESS" "$USDC" "approve(address,uint256)" "$EXIT10" $MAX_ALLOWANCE > /dev/null
cast send --from "$ALICE_ADDRESS" "$WETH" "approve(address,uint256)" "$DEPOSIT_HELPER" $MAX_ALLOWANCE > /dev/null
cast send --from "$ALICE_ADDRESS" "$USDC" "approve(address,uint256)" "$DEPOSIT_HELPER" $MAX_ALLOWANCE > /dev/null

# charlie and dave join the bootstrap phase
cast send --from "$CHARLIE_ADDRESS" "$WETH" "approve(address,uint256)" "$EXIT10" $MAX_ALLOWANCE > /dev/null
cast send --from "$CHARLIE_ADDRESS" "$USDC" "approve(address,uint256)" "$EXIT10" $MAX_ALLOWANCE > /dev/null
cast send --from "$DAVE_ADDRESS" "$WETH" "approve(address,uint256)" "$EXIT10" $MAX_ALLOWANCE > /dev/null
cast send --from "$DAVE_ADDRESS" "$USDC" "approve(address,uint256)" "$EXIT10" $MAX_ALLOWANCE > /dev/null

cast send --from "$CHARLIE_ADDRESS" --value "2000$DEC18" "$EXIT10" "bootstrapLock((address,uint256,uint256,uint256,uint256,uint256))" "($CHARLIE_ADDRESS,200000$DEC6,0,0,0,$DEADLINE)"
cast send --from "$DAVE_ADDRESS" --value "500$DEC18" "$EXIT10" "bootstrapLock((address,uint256,uint256,uint256,uint256,uint256))" "($DAVE_ADDRESS,50000$DEC6,0,0,0,$DEADLINE)"


