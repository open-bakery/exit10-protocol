#!/bin/bash

export ETH_FROM=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
MAX_ALLOWANCE="0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
DEADLINE=16805241220

DEC_6="000000"
DEC_18="000000000000000000"
DEC_A=$DEC_6
DEC_B=$DEC_18

LIQ_2="113417837328433" # liquidity for adding 2000 usdc + 2 eth
LIQ_4="226835674656867" # etc.
LIQ_8="453671349313735"
LIQ_16="907342698627470"
LIQ_32="1814685397254940"
LIQ_64="3629370794509880"

SD="$(dirname "$(readlink -f "$0")")"
source <(grep "=" "$SD/../.env")
source <(grep "=" "$SD/../config/$DEPLOYMENT/exit10.ini")

ALICE=$ALICE_ADDRESS
BOB=$BOB_ADDRESS
CHARLIE=$CHARLIE_ADDRESS
DAVE=$DAVE_ADDRESS
A=$ALICE
B=$BOB
C=$CHARLIE
D=$DAVE
MC=$MASTERCHEF
MCE=$MASTERCHEF_EXIT

echo "A=$A"
echo "B=$B"
echo "C=$C"
echo "D=$D"

# dynamic variables
bondId=0
bondLiquidity=("0")

function from_hex() {
  hex=$(echo $1 | cut -c 3-1000)
  echo $((16#$hex))
}

function extract_contract_address() {
  cat < /dev/stdin | grep contractAddress | awk '{ print $2 }' | cut -c 3-43 | tr '[:upper:]' '[:lower:]'
}

function skip_day() {
  sec=$((86400 * $1))
  echo "skipping $1 day ($sec sec)"
  cast rpc evm_increaseTime $sec > /dev/null
  cast rpc evm_mine > /dev/null
}

function approve() {
  echo "$1: approve $3 $2"
  cast send --from "$1" "$3" "approve(address,uint256)" "$2" $MAX_ALLOWANCE > /dev/null
}

function approve_all() {
  approve "$A" "$1" "$2"
  approve "$B" "$1" "$2"
  approve "$C" "$1" "$2"
}

function unapprove() {
  echo "$1: unapprove $3 $2"
  cast send --from "$1" "$3" "approve(address,uint256)" "$2" 0 > /dev/null
}

function liq_params() {
  if [ $TOKEN_OUT_FIRST -eq 1 ]
  then
    echo "$1$DEC_A,$2$DEC_B"
  else
    echo "$2$DEC_B,$1$DEC_A"
  fi
}

function bootstrap_lock() {
  echo "$1: bootstrapLock $2"
  cast send --from "$1" --value "$3$DEC_B" "$EXIT10" "bootstrapLock((address,uint256,uint256,uint256,uint256,uint256))" "($1,$(liq_params $2 0),0,0,$DEADLINE)" > /dev/null
}

function create_bond() {
  bondId=$((bondId+1))
  echo "$1: createBond $bondId ($2+$3)"
  cast send --from "$1" "$EXIT10" "createBond((address,uint256,uint256,uint256,uint256,uint256))" "($1,$(liq_params $2 $3),0,0,$DEADLINE)" > /dev/null
#  cast send --from "$1" "$EXIT10" "createBond((address,uint256,uint256,uint256,uint256,uint256))" "($1,$2$DEC_A,$3$DEC_B,0,0,$DEADLINE)" > /dev/null
  liquidity=$(cast call "$EXIT10" "getBondData(uint256)" "$bondId" | cut -c 1-66)
  liquidityDec=$(from_hex $liquidity)
  bondLiquidity+=("$liquidityDec")
}

function convert_bond() {
  liquidity=${bondLiquidity[$2]}
  echo "$1: convertBond $2 (liquidity: $liquidity)"
  cast send --from "$1" "$EXIT10" "convertBond(uint256,(uint128,uint256,uint256,uint256))" "$2" "($liquidity,0,0,$DEADLINE)" > /dev/null
}

function cancel_bond() {
  liquidity=${bondLiquidity[$2]}
  echo "$1: cancelBond $2 (liquidity: $liquidity)"
  cast send --from "$1" "$EXIT10" "cancelBond(uint256,(uint128,uint256,uint256,uint256))" "$2" "($liquidity,0,0,$DEADLINE)" > /dev/null
}

function swap_usdc_weth() {
  echo "$1: swap usdc->weth $2"
  cast send --from "$1" "$UNISWAP_V3_ROUTER" "exactInputSingle((address,address,uint24,address,uint256,uint256,uint256,uint160))" "($USDC,$WETH,500,$1,$DEADLINE,$2$DEC_A,0,0)" > /dev/null
}

function swap_weth_usdc() {
  echo "$1: swap weth->usdc $2"
  cast send --from "$1" "$UNISWAP_V3_ROUTER" "exactInputSingle((address,address,uint24,address,uint256,uint256,uint256,uint160))" "($WETH,$USDC,500,$1,$DEADLINE,$2$DEC_B,0,0)" > /dev/null
}

function swap_usdc_exit() {
  echo "$1: swap usdc->exit $2"
  cast send --from "$1" "$UNISWAP_V2_ROUTER" "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)" "$2$DEC_A" "0" "[$USDC,$EXIT]" "$1" "$DEADLINE" > /dev/null
}

function swap_exit_usdc() {
  echo "$1: swap exit->usdc $2"
  echo "balance: $(cast call $EXIT "balanceOf(address)" $1)"
  cast send --from "$1" "$UNISWAP_V2_ROUTER" "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)" "$2$DEC_18" "0" "[$EXIT,$USDC]" "$1" "$DEADLINE" > /dev/null
}

function stake() {
  # stake <from> <masterchef> <pool> <amount>
  cast send --from "$1" "$2" "deposit(uint256,uint256)" "$3" "$4$DEC_18" > /dev/null
}

function stake_sto() {
  echo "$1: stake STO $2"
  stake "$1" $MC "0" $2
}

function stake_boot() {
  echo "$1: stake BOOT $2"
  stake "$1" $MC "1" $2
}

function stake_blp() {
  echo "$1: stake BLP $2"
  stake "$1" $MCE "1" $2
}

function stake_all_blp() {
  echo "$1: stake all BLP"
  local BALANCE=$(cast call "$BALANCE" "balanceOf(address)" "$1")
  stake "$1" $MCE "1" $BALANCE
}

function lp_exit() {
  echo "$1: LP EXIT $2 $3"
  echo "lp exit $2$DEC_A $3$DEC_18"
  cast send --from "$1" "$UNISWAP_V2_ROUTER" "addLiquidity(address,address,uint256,uint256,uint256,uint256,address,uint256)" "$USDC" "$EXIT" "$2$DEC_A" "$3$DEC_18" "0" "0" "$1" "$DEADLINE" > /dev/null
}

function lp_all_exit() {
  echo "$1: LP all EXIT"
  local BALANCE=$(cast call "$EXIT" "balanceOf(address)" "$1")
  echo "lp all exit $BALANCE"
  cast send --from "$1" "$UNISWAP_V2_ROUTER" "addLiquidity(address,address,uint256,uint256,uint256,uint256,address,uint256)" "$USDC" "$EXIT" "1000000$DEC_A" "$BALANCE" "0" "0" "$1" "$DEADLINE" > /dev/null
}

function stake_exit_lp() {
  echo "$1: stake EXIT LP $2"
  stake "$1" $MCE "0" $2
}

function stake_all_exit_lp() {
  echo "$1: stake all EXIT"
  local BALANCE=$(cast call "$EXIT_LP" "balanceOf(address)" "$1")
  stake "$1" $MCE "0" $BALANCE
}


function update_fees() {
  echo "$1: updateFees"
  cast send --from "$1" "$FEE_SPLITTER" "updateFees(uint256)" "10000$DEC_A" > /dev/null
}

function swap_usdc_weth_back_and_forth() {
  swap_usdc_weth $1 3000000
  cast rpc evm_increaseTime 60 > /dev/null
  swap_weth_usdc $1 2000
  cast rpc evm_increaseTime 60 > /dev/null
}

function generate_volume() {
  swap_usdc_weth_back_and_forth $B
  swap_usdc_weth_back_and_forth $B
  swap_usdc_weth_back_and_forth $B
  swap_usdc_weth_back_and_forth $B

  swap_usdc_weth_back_and_forth $C
  swap_usdc_weth_back_and_forth $C
  swap_usdc_weth_back_and_forth $C
  swap_usdc_weth_back_and_forth $C
}

# provide exit liquidity too

# distribute usdc
cast send --from "$DEPLOYER_ADDRESS" "$USDC" "transfer(address,uint256)" "$A" "500000$DEC_A" > /dev/null
cast send --from "$DEPLOYER_ADDRESS" "$USDC" "transfer(address,uint256)" "$B" "100000000$DEC_A" > /dev/null
cast send --from "$DEPLOYER_ADDRESS" "$USDC" "transfer(address,uint256)" "$C" "100000000$DEC_A" > /dev/null
cast send --from "$DEPLOYER_ADDRESS" "$USDC" "transfer(address,uint256)" "$D" "100000$DEC_A" > /dev/null

# alice doesn't want that much eth. makes the ui more difficult to work with. She'll have 100 WETH and 400 ETH
cast send --from "$A" --value "100$DEC_B" "$WETH" "deposit()" > /dev/null
cast send --from "$A" --value "999500$DEC_B" > /dev/null

cast send --from "$B" --value "5000$DEC_B" "$WETH" "deposit()" > /dev/null
cast send --from "$C" --value "5000$DEC_B" "$WETH" "deposit()" > /dev/null


# mint exit10 position in advance, not strictly necessary, might not do it in some scenarios
# not even not necessary but pointless too I think... let's keep this commented and delete later
#cast send --from "$ALICE_ADDRESS" "$WETH" "approve(address,uint256)" "$UNISWAP_V3_NPM" $MAX_ALLOWANCE > /dev/null
#cast send --from "$ALICE_ADDRESS" "$USDC" "approve(address,uint256)" "$UNISWAP_V3_NPM" $MAX_ALLOWANCE > /dev/null
#cast send --from "$ALICE_ADDRESS" "$UNISWAP_V3_NPM" "mint((address,address,uint24,int24,int24,uint256,uint256,uint256,uint256,address,uint256))(uint256,uint128,uint256,uint256)" "($USDC,$WETH,500,$LOWER_TICK,$UPPER_TICK,100000000000,500000000000000000000,0,0,$ALICE_ADDRESS,10000000000000000000000000000)" > /dev/null

# alice, charlie and bob approve pretty much everthing
echo "approve exit"
approve_all "$EXIT10" "$WETH"
approve_all "$EXIT10" "$USDC"
echo "approve deposit helper"
approve_all "$DEPOSIT_HELPER" "$WETH"
approve_all "$DEPOSIT_HELPER" "$USDC"
echo "approve masterchef"
approve_all "$MC" "$STO"
approve_all "$MC" "$BOOT"
echo "approve masterchefExits"
approve_all "$MASTERCHEF_EXIT" "$BLP"
approve_all "$MASTERCHEF_EXIT" "$EXIT_LP"
echo "approve v3 router"
approve_all "$UNISWAP_V3_ROUTER" "$USDC"
approve_all "$UNISWAP_V3_ROUTER" "$WETH"
echo "approve v2 router"
approve_all "$UNISWAP_V2_ROUTER" "$USDC"
approve_all "$UNISWAP_V2_ROUTER" "$EXIT"


# first phase -> bootstrap ongoing

echo "bootstrap 1"
bootstrap_lock "$C" "200000" "200"
skip_day 1
echo "bootstrap 2"
bootstrap_lock "$B" "100000" "100"
skip_day 1
echo "bootstrap 3"
bootstrap_lock "$A" "100000" "100"
skip_day 1
skip_day 1
echo "bootstrap 4"
bootstrap_lock "$B" "200000" "200"
skip_day 1
echo "bootstrap 5"
bootstrap_lock "$C" "200000" "200"
skip_day 1
bootstrap_lock "$C" "200000" "200"
skip_day 1
skip_day 1



#create_bond "$A" "4000" "4"
#create_bond "$A" "8000" "8"
#create_bond "$A" "16000" "16"
#create_bond "$A" "32000" "32"
#create_bond "$A" "64000" "64"


# day 1
create_bond "$B" "4000" "4" # 1
echo "Bond 1 liquidity: $BOND1_LIQ"
create_bond "$A" "8000" "8" # 2
create_bond "$A" "8000" "8" # 3
stake_boot "$A" "420000"
stake_boot "$B" "850000"
stake_boot "$C" "1000000"
skip_day 1

# day 2
create_bond "$C" "32000" "32" # 4
swap_usdc_weth "$B" "2000000"
skip_day 1
skip_day 1
skip_day 1
skip_day 1

# day 6
create_bond "$B" "8000" "8" # 5
create_bond "$A" "16000" "16" # 6
# this one here fails for some reason (OLD)
#update_fees "$A"
skip_day 1
skip_day 1

# day 8
create_bond "$B" "8000" "8" # 7
swap_usdc_weth "$C" "3000000"
skip_day 1

# day 9
create_bond "$C" "16000" "16" # 8
skip_day 1
skip_day 1
skip_day 1
skip_day 1
skip_day 1

# day 14
create_bond "$B" "32000" "32" # 9
create_bond "$C" "8000" "8" # 10
swap_weth_usdc "$C" "1200"
skip_day 1
skip_day 1

# day 16
swap_usdc_weth "$C" "2000000"
create_bond "$A" "16000" "16" # 11
skip_day 1
skip_day 1


# day 18
create_bond "$C" "32000" "32" # 12
update_fees "$A"
skip_day 1


# day 19: first EXIT minted
convert_bond "$A" 2
echo "BLP addr: $BLP";
echo "A BLP Balance:"
cast call "$BLP" "balanceOf(address)" "$A"
stake_blp "$A" "6400"
# cast call "$EXIT" "balanceOf(address)" "$A"
# balance at this point: 824.781027387355204012
lp_exit "$A" "4000" "400"
skip_day 1

# day 20
cancel_bond "$A" 3
swap_usdc_weth "$B" "2000000"
swap_usdc_exit "$B" "4000"
skip_day 1
skip_day 1

# day 22
swap_usdc_exit "$A" "4000"
create_bond "$A" "32000" "32" # 13
skip_day 1

# day 23
generate_volume
update_fees "$B"

convert_bond "$C" 4
stake_blp "$C" "12000"
lp_all_exit "$C"
swap_exit_usdc "$A" "300"
skip_day 1

# day 24
generate_volume
update_fees "$B"
swap_usdc_exit "$C" "6000"
create_bond "$B" "32000" "32" # 14
update_fees "$A"
skip_day 1


# day 25
generate_volume
update_fees "$B"
convert_bond "$C" 8
swap_exit_usdc "$C" "150"
skip_day 1

# day 26
generate_volume
update_fees "$B"
skip_day 1

# day 27
generate_volume
update_fees "$B"
skip_day 1

# day 28
generate_volume
update_fees "$B"
convert_bond "$B" 9
cast call "$EXIT" "balanceOf(address)" "$C"
# balance at this point: 79 something
swap_exit_usdc "$C" "60"
skip_day 1

# day 29
skip_day 1

unapprove "$B" "$EXIT10" "$WETH"
unapprove "$B" "$EXIT10" "$USDC"
unapprove "$B" "$DEPOSIT_HELPER" "$WETH"
unapprove "$B" "$DEPOSIT_HELPER" "$USDC"
unapprove "$B" "$MC" "$STO"
unapprove "$B" "$MC" "$BOOT"
unapprove "$B" "$MCE" "$BLP"
unapprove "$B" "$MCE" "$EXIT_LP"