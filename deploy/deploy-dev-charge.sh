#!/bin/bash

SD="$(dirname "$(readlink -f "$0")")"
source "$SD/../.env";
source "$SD/../config/local.ini";

function pass_day() {
  cast rpc evm_increaseTime "86400" > /dev/null
  cast rpc evm_mine > /dev/null
}
function pass_2days() {
  cast rpc evm_increaseTime "172800" > /dev/null
  cast rpc evm_mine > /dev/null
}

function pass_4days() {
  cast rpc evm_increaseTime "345600" > /dev/null
  cast rpc evm_mine > /dev/null
}


# 15 days passed, bootstrap has ended

