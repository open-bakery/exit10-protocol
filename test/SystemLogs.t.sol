// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import { console } from 'forge-std/console.sol';
import { ERC20 } from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import { Script } from 'forge-std/Script.sol';
import { Strings } from '@openzeppelin/contracts/utils/Strings.sol';
import { FeeSplitter, ABaseExit10Test } from './ABaseExit10.t.sol';
import { AMasterchefBase } from './AMasterchefBase.t.sol';
import { DecimalStrings } from '../src/libraries/DecimalStrings.sol';

contract SystemLogsTest is ABaseExit10Test {
  mapping(address => string) userName;
  bool showAsInteger;
  address tokenOut;
  address tokenIn;
  uint256 deposit0;
  uint256 deposit1;

  function setUp() public override {
    super.setUp();
    _setupNames();
    _distributeSTO();
    tokenOut = exit10.TOKEN_OUT();
    tokenIn = exit10.TOKEN_IN();
    (deposit0, deposit1) = (tokenOut < tokenIn)
      ? (_tokenAmount(address(tokenOut), 100000), _tokenAmount(address(tokenIn), 100))
      : (_tokenAmount(address(tokenIn), 100), _tokenAmount(address(tokenOut), 100000));
    showAsInteger = false;
  }

  function testScenario_0() public {
    _bootstrapAndStakeBootAll();
    _stakeStoAll(true);
    _generateClaimAndDistributeFees();
    _displayRewardBalanceMasterchefs();
    _displayBuckets();
    _skip(bootstrapDuration);
    uint256 bondIdA = _createBond(alice, deposit0, deposit1);
    uint256 bondIdB = _createBond(bob, deposit0, deposit1);
    uint256 bondIdC = _createBond(charlie, deposit0, deposit1);
    _displayBuckets();
    _skip(1);
    _convertBond(bondIdA, alice);
    _skip(accrualParameter);
    _convertBond(bondIdB, bob);
    _skip(accrualParameter * 4);
    _convertBond(bondIdC, charlie);
    _stakeBlpAll(true);
    _displayBuckets();
    _skip(accrualParameter);
    _generateClaimAndDistributeFees();
    _distributeRewardsToMasterchefs();
    _skip(accrualParameter);
    _claimEthRewards(alice, address(masterchef), 0);
    _claimEthRewards(bob, address(masterchef), 0);
    _claimEthRewards(charlie, address(masterchef), 0);
    _claimEthRewards(alice, address(masterchef), 1);
    _claimEthRewards(bob, address(masterchef), 1);
    _claimEthRewards(charlie, address(masterchef), 1);
    _stakeBlpAll(false);
    _stakeBlpAll(true);
    _lpAndStakeLpAll();
    _toTheMoon();
    _skip(rewardsDurationExit);
    _claimExitRewards(alice);
    _claimExitRewards(bob);
    _claimExitRewards(charlie);
    _exit10();
    _stakeBootstrapAll(false);
    _stakeStoAll(false);
    _claimFinalAll();
    _displayTreasury();
    _displaySupplies();
    _displayRewardBalanceMasterchefs();
    _skip(rewardsDurationExit);
    _unstakeLpAndBreakLpAll();
    _stakeBlpAll(false);
    _exitClaimAll();
    _displayRewardBalanceMasterchefs();
  }

  function testScenario_1() public {
    _displayPrice();
    _skip(bootstrapDuration);
    uint256 bondIdA = _createBond(alice, deposit0, deposit1);
    uint256 bondIdB = _createBond(bob, deposit0, deposit1);
    uint256 bondIdC = _createBond(charlie, deposit0, deposit1);
    _displayBuckets();
    _skip(1);
    _convertBond(bondIdA, alice);
    _skip(accrualParameter);
    _convertBond(bondIdB, bob);
    _skip(accrualParameter * 4);
    _convertBond(bondIdC, charlie);
    _displayBuckets();
    _generateClaimAndDistributeFees();
    _distributeRewardsToMasterchefs();
    _stakeBlpAll(true);
    _skip(accrualParameter);
    _stakeBlpAll(false);
    _redeem(alice);
    _redeem(bob);
    _redeem(charlie);
    _toTheMoon();
    _exit10();
    _lpExit(alice);
    _stake(alice, address(masterchefExit), 0, lp);
    _unstake(alice, address(masterchefExit), 0, lp);
    _breakLP(alice);
    _exitClaimAll();
    _stoClaimAll();
    _displayTreasury();
    _displaySupplies();
  }

  function testScenario_2() public {
    _bootstrapAll();
    _generateClaimAndDistributeFees();
    _displayRewardBalanceMasterchefs();
    _toTheMoon();
    _exit10();
    _stoClaimAll();
    _bootstrapClaimAll();
    _displayTreasury();
    _displaySupplies();
  }

  function testScenario_3() public {
    _bootstrapAndStakeBootAll();
    _stake(alice, address(masterchef), 0, address(sto));
    _generateClaimAndDistributeFees();
    _displayRewardBalanceMasterchefs();
    _displayBuckets();
    _skip(bootstrapDuration);
    uint256 bondId = _createBond(alice, deposit0, deposit1);
    _skip(accrualParameter);
    _generateFees();
    _generateClaimAndDistributeFees();
    _distributeRewardsToMasterchefs();
    _convertBond(bondId, alice);
    _displayBuckets();
    _stake(alice, address(masterchefExit), 1, address(blp));
    _skip(accrualParameter);
    _unstake(alice, address(masterchefExit), 1, address(blp));
    _lpExit(alice);
    _stake(alice, address(masterchefExit), 0, lp);
    _skip(accrualParameter);
    _claimExitRewards(alice);
    _generateClaimAndDistributeFees();
    _distributeRewardsToMasterchefs();
    _skip(accrualParameter);
    _claimEthRewards(bob, address(masterchef), 1);
    _claimEthRewards(alice, address(masterchef), 0);
    _stake(alice, address(masterchefExit), 1, address(blp));
    _unstake(alice, address(masterchefExit), 0, lp);
    _skip(accrualParameter);
    _stake(alice, address(masterchefExit), 0, lp);
    _skip(accrualParameter);
    _unstake(alice, address(masterchefExit), 0, lp);
    _toTheMoon();
    _skip(accrualParameter);
    _claimEthRewards(alice, address(masterchef), 0);
    _unstake(alice, address(masterchefExit), 1, address(blp));
    _redeem(alice);
    _exit10();
    _stake(alice, address(masterchefExit), 0, lp);
    _unstake(alice, address(masterchefExit), 0, lp);
    _breakLP(alice);
    _exitClaim(alice);
    _unstake(alice, address(masterchef), 0, address(sto));
    _stoClaim(alice);
    _unstake(alice, address(masterchef), 1, address(boot));
    _bootstrapClaim(alice);
    _displayTreasury();
    _unstake(bob, address(masterchef), 1, address(boot));
    _unstake(charlie, address(masterchef), 1, address(boot));
    _stoClaim(bob);
    _stoClaim(charlie);
    _bootstrapClaim(bob);
    _bootstrapClaim(charlie);
    _displayTreasury();
    _displaySupplies();
    _displayRewardBalanceMasterchefs();
  }

  function _exitClaimAll() internal {
    _exitClaim(alice);
    _exitClaim(bob);
    _exitClaim(charlie);
  }

  function _stoClaimAll() internal {
    _stoClaim(alice);
    _stoClaim(bob);
    _stoClaim(charlie);
  }

  function _bootstrapClaimAll() internal {
    _bootstrapClaim(alice);
    _bootstrapClaim(bob);
    _bootstrapClaim(charlie);
  }

  function _claimFinalAll() internal {
    _exitClaimAll();
    _stoClaimAll();
    _bootstrapClaimAll();
  }

  function _bootstrapAll() internal {
    uint256 da0;
    uint256 db0;
    uint256 dc0;
    uint256 da1;
    uint256 db1;
    uint256 dc1;

    (da0, db0, dc0) = (_tokenAmount(tokenOut, 10_000), _tokenAmount(tokenOut, 1_000), _tokenAmount(tokenOut, 100_000));
    (da1, db1, dc1) = (_tokenAmount(tokenIn, 10), _tokenAmount(tokenIn, 1), _tokenAmount(tokenIn, 100));

    if (tokenIn < tokenOut) {
      (da0, db0, dc0) = (da1, db1, dc1);
      (da1, db1, dc1) = (da0, db0, dc0);
    }

    (, , uint256 at0, uint256 at1) = _lockBootstrap(alice, da0, da1);
    (, , uint256 bt0, uint256 bt1) = _lockBootstrap(bob, db0, db1);
    (, , uint256 ct0, uint256 ct1) = _lockBootstrap(charlie, dc0, dc1);

    _displayTotal('TOTAL BOOTSTRAPPED', at0 + bt0 + ct0, at1 + bt1 + ct1);
    _displayBuckets();
  }

  function _bootstrapAndStakeBootAll() internal {
    _bootstrapAll();
    _stakeBootstrapAll(true);
  }

  function _stakeBootstrapAll(bool _isStake) internal {
    if (_isStake) {
      _stake(alice, address(masterchef), 1, address(boot));
      _stake(bob, address(masterchef), 1, address(boot));
      _stake(charlie, address(masterchef), 1, address(boot));
    } else {
      _unstake(alice, address(masterchef), 1, address(boot));
      _unstake(bob, address(masterchef), 1, address(boot));
      _unstake(charlie, address(masterchef), 1, address(boot));
    }
  }

  function _stakeStoAll(bool _isStake) internal {
    if (_isStake) {
      _stake(alice, address(masterchef), 0, address(sto));
      _stake(bob, address(masterchef), 0, address(sto));
      _stake(charlie, address(masterchef), 0, address(sto));
    } else {
      _unstake(alice, address(masterchef), 0, address(sto));
      _unstake(bob, address(masterchef), 0, address(sto));
      _unstake(charlie, address(masterchef), 0, address(sto));
    }
  }

  function _lpAndStakeLpAll() internal {
    _lpAll();
    _stakeLpAll(true);
  }

  function _lpAll() internal {
    _lpExit(alice);
    _lpExit(bob);
    _lpExit(charlie);
  }

  function _breakLpAll() internal {
    _breakLP(alice);
    _breakLP(bob);
    _breakLP(charlie);
  }

  function _unstakeLpAndBreakLpAll() internal {
    _stakeLpAll(false);
    _breakLpAll();
  }

  function _stakeLpAll(bool _isStake) internal {
    if (_isStake) {
      _stake(alice, address(masterchefExit), 0, lp);
      _stake(bob, address(masterchefExit), 0, lp);
      _stake(charlie, address(masterchefExit), 0, lp);
    } else {
      _unstake(alice, address(masterchefExit), 0, lp);
      _unstake(bob, address(masterchefExit), 0, lp);
      _unstake(charlie, address(masterchefExit), 0, lp);
    }
  }

  function _stakeBlpAll(bool _isStake) internal {
    if (_isStake) {
      _stake(alice, address(masterchefExit), 1, address(blp));
      _stake(bob, address(masterchefExit), 1, address(blp));
      _stake(charlie, address(masterchefExit), 1, address(blp));
    } else {
      _unstake(alice, address(masterchefExit), 1, address(blp));
      _unstake(bob, address(masterchefExit), 1, address(blp));
      _unstake(charlie, address(masterchefExit), 1, address(blp));
    }
  }

  function _lockBootstrap(
    address _user,
    uint256 _token0Amount,
    uint256 _token1Amount
  ) internal returns (uint256 tokenId, uint128 liquidityAdded, uint256 amountAdded0, uint256 amountAdded1) {
    deal(address(token0), _user, _token0Amount);
    deal(address(token1), _user, _token1Amount);

    vm.startPrank(_user);
    ERC20(token0).approve(address(exit10), _token0Amount);
    ERC20(token1).approve(address(exit10), _token1Amount);
    (tokenId, liquidityAdded, amountAdded0, amountAdded1) = exit10.bootstrapLock(
      _addLiquidityParams(_user, _token0Amount, _token1Amount)
    );
    vm.stopPrank();

    string memory log0 = string.concat('User: ', userName[_user]);
    string memory log1 = _displayAmount('Amount', address(token0), amountAdded0);
    string memory log2 = _displayAmount('Amount', address(token1), amountAdded1);
    string memory log3 = _displayAmount('Sum', usdc, _getSumInUSDC(amountAdded0, amountAdded1));
    _title('ENTERING BOOTSTRAP PHASE');
    console.log(log0);
    console.log(log1);
    console.log(log2);
    console.log(log3);
    _spacer();
  }

  function _createBond(address _user, uint256 _amount0, uint256 _amount1) internal returns (uint _bondId) {
    deal(address(token0), _user, _amount0);
    deal(address(token1), _user, _amount1);

    vm.startPrank(_user);
    ERC20(address(token0)).approve(address(exit10), _amount0);
    ERC20(address(token1)).approve(address(exit10), _amount1);
    uint256 amountAdded0;
    uint256 amountAdded1;
    (_bondId, , amountAdded0, amountAdded1) = exit10.createBond(_addLiquidityParams(_user, _amount0, _amount1));
    vm.stopPrank();

    string memory log0 = string.concat('User: ', userName[_user]);
    string memory log1 = _displayAmount('Amount', address(token0), amountAdded0);
    string memory log2 = _displayAmount('Amount', address(token1), amountAdded1);
    string memory log3 = _displayAmount('Sum', usdc, _getSumInUSDC(amountAdded0, amountAdded1));
    _title('CREATING BOND');
    console.log(log0);
    console.log(log1);
    console.log(log2);
    console.log(log3);
    _spacer();
  }

  function _cancelBond(uint _bondId, address _user) internal {
    (uint bondAmount, , , , ) = exit10.getBondData(_bondId);
    vm.startPrank(_user);
    (uint usdcAmount, uint wethAmount) = exit10.cancelBond(_bondId, _removeLiquidityParams(bondAmount));
    vm.stopPrank();

    string memory log0 = string.concat('User: ', userName[_user]);
    string memory log1 = string.concat('Amount Bond: ', Strings.toString(bondAmount));
    string memory log2 = _displayAmount('Amount', usdc, usdcAmount);
    string memory log3 = _displayAmount('Amount', weth, wethAmount);
    string memory log4 = _displayAmount('Sum', usdc, _getSumInUSDC(usdcAmount, wethAmount));
    _title('CANCELLED BOND');
    console.log(log0);
    console.log(log1);
    console.log(log2);
    console.log(log3);
    console.log(log4);
    _spacer();
  }

  function _convertBond(uint _bondId, address _user) internal {
    (uint bondAmount, , , , ) = exit10.getBondData(_bondId);
    vm.startPrank(_user);
    uint blpTokenAmount = exit10.convertBond(_bondId, _removeLiquidityParams(bondAmount));
    vm.stopPrank();

    string memory log0 = string.concat('User: ', userName[_user]);
    string memory log1 = string.concat('Amount Bond: ', Strings.toString(bondAmount));
    string memory log2 = _displayAmount('Amount', address(blp), blpTokenAmount);
    _title('BOND CONVERTED');
    console.log(log0);
    console.log(log1);
    console.log(log2);
    _spacer();
  }

  function _redeem(address _user) internal {
    uint256 balance = blp.balanceOf(_user);
    vm.startPrank(_user);
    (uint256 amountRemoved0, uint256 amountRemoved1) = exit10.redeem(
      _removeLiquidityParams(balance / exit10.TOKEN_MULTIPLIER())
    );
    vm.stopPrank();

    string memory log0 = string.concat('User: ', userName[_user]);
    string memory log1 = _displayAmount('Amount', address(blp), balance);
    string memory log2 = _displayAmount('Amount', usdc, amountRemoved0);
    string memory log3 = _displayAmount('Amount', weth, amountRemoved1);
    string memory log4 = _displayAmount('Sum', usdc, _getSumInUSDC(amountRemoved0, amountRemoved1));
    _title('REDEEMED BLP');
    console.log(log0);
    console.log(log1);
    console.log(log2);
    console.log(log3);
    console.log(log4);
    _spacer();
  }

  function _exit10() internal {
    exit10.exit10();

    _title('EXIT @ 10K ETH');
    _spacer();
    _displayPrice();
    _displayTreasury();
  }

  function _bootstrapClaim(address _user) internal {
    uint256 balance = boot.balanceOf(_user);
    vm.startPrank(_user);
    uint256 claim = exit10.bootstrapClaim();
    vm.stopPrank();

    string memory log0 = string.concat('User: ', userName[_user]);
    string memory log1 = _displayAmount('Burned', address(boot), balance);
    string memory log2 = _displayAmount('Claimed', usdc, claim);
    _title('CLAIMED BOOTSTRAP');
    console.log(log0);
    console.log(log1);
    console.log(log2);
    _spacer();
  }

  function _stoClaim(address _user) internal {
    uint256 balance = sto.balanceOf(_user);
    vm.startPrank(_user);
    uint256 claim = exit10.stoClaim();
    vm.stopPrank();

    string memory log0 = string.concat('User: ', userName[_user]);
    string memory log1 = _displayAmount('Burned', address(sto), balance);
    string memory log2 = _displayAmount('Claimed', usdc, claim);
    _title('CLAIMED STO');
    console.log(log0);
    console.log(log1);
    console.log(log2);
    _spacer();
  }

  function _exitClaim(address _user) internal {
    uint256 balance = exit.balanceOf(_user);
    vm.startPrank(_user);
    (uint256 claimTokenOut, uint256 claimTokenIn, ) = exit10.exitClaim();
    vm.stopPrank();

    string memory log0 = string.concat('User: ', userName[_user]);
    string memory log1 = _displayAmount('Burned', address(exit), balance);
    string memory log2 = _displayAmount('Claimed', tokenOut, claimTokenOut);
    string memory log3 = _displayAmount('Claimed', tokenIn, claimTokenIn);
    _title('CLAIMED EXIT');
    console.log(log0);
    console.log(log1);
    console.log(log2);
    console.log(log3);
    _spacer();
  }

  function _toTheMoon() internal {
    _title('TO THE MOON');
    _eth10k();
    _spacer();
    _displayPrice();
  }

  function _skip(uint256 _seconds) internal {
    skip(_seconds);

    _title('TIME TRAVEL');
    console.log('Fastforward: ', _seconds);
    _spacer();
  }

  function _generateFees() internal {
    _generateFees(usdc, weth, _tokenAmount(usdc, 100_000_000));
    // Skips oracle requirement
    skip(ORACLE_SECONDS);
    _title('GENERATING FEE');
    _spacer();
    _displayPrice();
  }

  function _generateClaimAndDistributeFees() internal {
    _generateFees();
    exit10.claimAndDistributeFees();

    _title('FEE DISTRIBUTION');
    _displayBalances('Fee Splitter Balance', feeSplitter, usdc, weth);
    _spacer();
  }

  function _distributeRewardsToMasterchefs() internal {
    uint256 prevBalanceMc0 = ERC20(weth).balanceOf(address(masterchef));
    uint256 prevBalanceMc1 = ERC20(weth).balanceOf(address(exit10));
    uint256 usdcToSell = ERC20(usdc).balanceOf(address(feeSplitter));
    uint256 ETHAcquired = FeeSplitter(feeSplitter).updateFees(usdcToSell);
    uint256 depositedRewardsMc0 = ERC20(weth).balanceOf(address(masterchef)) - prevBalanceMc0;
    uint256 depositedRewardsMc1 = ERC20(weth).balanceOf(address(exit10)) - prevBalanceMc1;

    _title('WETH REWARD DISTRIBUTION');
    console.log(_displayAmount('Total Sold', usdc, usdcToSell));
    console.log(_displayAmount('Total Acquired', weth, ETHAcquired));
    console.log(_displayAmount('Distributed To masterchef', weth, depositedRewardsMc0));
    console.log(_displayAmount('Distributed To exit10', weth, depositedRewardsMc1));
    _spacer();
    _displayRewardBalanceMasterchefs();
  }

  function _lpExit(address _user) internal returns (uint _amountAddedExit, uint _amountAddedUsdc, uint _liquidity) {
    uint balanceExit = exit.balanceOf(_user);
    uint amountUsdc = _tokenAmount(usdc, balanceExit / 1e6);
    console.log('balanceExit: ', balanceExit);
    deal(usdc, _user, amountUsdc);
    vm.startPrank(_user);
    (_amountAddedExit, _amountAddedUsdc, _liquidity) = _addLiquidity(address(exit), usdc, balanceExit, amountUsdc);
    vm.stopPrank();
    ERC20(lp).transfer(_user, _liquidity);

    string memory log0 = string.concat('User: ', userName[_user]);
    string memory log1 = _displayAmount('Added', address(exit), _amountAddedExit);
    string memory log2 = _displayAmount('USDC added: ', usdc, _amountAddedUsdc);
    string memory log3 = _displayAmount('Liquidity added: ', lp, _liquidity);
    _title('PROVIDING EXIT/USDC LIQUIDITY');
    console.log(log0);
    console.log(log1);
    console.log(log2);
    console.log(log3);
    _spacer();
  }

  function _breakLP(address _user) internal {
    uint256 balance = ERC20(lp).balanceOf(_user);
    vm.startPrank(_user);
    _maxApprove(lp, address(UNISWAP_V2_ROUTER));
    (uint256 amount0, uint256 amount1) = UNISWAP_V2_ROUTER.removeLiquidity(
      usdc,
      address(exit),
      balance,
      0,
      0,
      _user,
      block.timestamp
    );
    vm.stopPrank();
    string memory log0 = string.concat('User: ', userName[_user]);
    string memory log1 = _displayAmount('Removed: ', address(exit), amount1);
    string memory log2 = _displayAmount('Removed: ', usdc, amount0);
    string memory log3 = _displayAmount('Liquidity burned: ', address(lp), balance);
    _title('REMOVING EXIT/USDC LIQUIDITY');
    console.log(log0);
    console.log(log1);
    console.log(log2);
    console.log(log3);
    _spacer();
  }

  function _stake(address _user, address _mc, uint256 _pid, address _token) internal {
    address rewardToken = AMasterchefBase(_mc).REWARD_TOKEN();
    uint256 prevBalanceReward = ERC20(rewardToken).balanceOf(_user);
    uint256 balance = ERC20(_token).balanceOf(_user);

    vm.startPrank(_user);
    ERC20(_token).approve(address(_mc), balance);
    AMasterchefBase(_mc).deposit(_pid, balance);
    vm.stopPrank();
    uint256 postBalanceReward = ERC20(rewardToken).balanceOf(_user);
    uint256 rewardAmount = postBalanceReward - prevBalanceReward;

    string memory log0 = string.concat('User: ', userName[_user]);
    string memory log1 = _displayAmount('Amount', _token, balance);
    string memory log2 = _displayAmount('Reward Amount', rewardToken, rewardAmount);
    _title('STAKING IN MASTERCHEF');
    console.log(log0);
    console.log(log1);
    console.log(log2);
    _spacer();
  }

  function _unstake(address _user, address _mc, uint256 _pid, address _token) internal {
    address rewardToken = AMasterchefBase(_mc).REWARD_TOKEN();
    uint256 prevBalanceReward = ERC20(rewardToken).balanceOf(_user);
    (uint256 staked, ) = AMasterchefBase(_mc).userInfo(_pid, _user);
    vm.startPrank(_user);
    AMasterchefBase(_mc).withdraw(_pid, staked);
    vm.stopPrank();
    uint256 postBalanceReward = ERC20(rewardToken).balanceOf(_user);
    uint256 rewardAmount = postBalanceReward - prevBalanceReward;

    string memory log0 = string.concat('User: ', userName[_user]);
    string memory log1 = _displayAmount('Amount', _token, staked);
    string memory log2 = _displayAmount('Reward Amount', rewardToken, rewardAmount);
    _title('UNSTAKING FROM MASTERCHEF');
    console.log(log0);
    console.log(log1);
    console.log(log2);
    _spacer();
  }

  function _claimExitRewards(address _user) internal {
    uint256 prevExitBalance = exit.balanceOf(_user);
    vm.startPrank(_user);
    masterchefExit.withdraw(0, 0);
    vm.stopPrank();
    uint256 claimedExit = exit.balanceOf(_user) - prevExitBalance;

    string memory log0 = string.concat('User: ', userName[_user]);
    string memory log1 = _displayAmount('Amount', address(exit), claimedExit);
    _title('CLAIMED EXIT IN MASTERCHEF');
    console.log(log0);
    console.log(log1);
    _spacer();
  }

  function _claimEthRewards(address _user, address _mc, uint256 _pid) internal {
    uint256 prevWethBalance = ERC20(weth).balanceOf(_user);
    vm.startPrank(_user);
    AMasterchefBase(_mc).withdraw(_pid, 0);
    vm.stopPrank();
    uint256 claimedWeth = ERC20(weth).balanceOf(_user) - prevWethBalance;

    string memory log0 = string.concat('User: ', userName[_user]);
    string memory log1 = _displayAmount('Amount', weth, claimedWeth);
    _title('CLAIMED WETH IN MASTERCHEF');
    console.log(log0);
    console.log(log1);
    _spacer();
  }

  function _setupNames() internal {
    userName[alice] = 'Alice';
    userName[bob] = 'Bob';
    userName[charlie] = 'Charlie';
  }

  function _distributeSTO() internal {
    vm.startPrank(address(exit10));
    sto.mint(alice, 100_000 ether);
    sto.mint(bob, 50_000 ether);
    sto.mint(charlie, 150_000 ether);
    vm.stopPrank();

    _maxApproveFrom(alice, address(sto), address(masterchef));
    _maxApproveFrom(bob, address(sto), address(masterchef));
    _maxApproveFrom(charlie, address(sto), address(masterchef));
  }

  function _displaySupplies() internal view {
    string memory log0 = _displayAmount('Total Supply', address(boot), boot.totalSupply());
    string memory log1 = _displayAmount('Total Supply', address(sto), sto.totalSupply());
    string memory log2 = _displayAmount('Total Supply', address(exit), exit.totalSupply());

    _title('DISPLAY SUPPLIES');
    console.log(log0);
    console.log(log1);
    console.log(log2);
    _spacer();
  }

  function _getSumInUSDC(uint256 amountUSD, uint256 amountETH) internal view returns (uint256) {
    return amountUSD + ((amountETH * _returnPriceInUSD()) / 1e18);
  }

  function _displayPrice() internal view {
    _title('ETH PRICE');
    console.log(_displayAmount('Price', usdc, _returnPriceInUSD()));
    _spacer();
  }

  function _displayRewardBalanceMasterchefs() internal view {
    _displayBalance('masterchef', address(masterchef), weth);
    _displayBalance('exit10', address(exit10), weth);
    _displayBalance('MasterchefExit', address(masterchefExit), address(exit));
  }

  function _displayTreasury() internal view {
    uint256 balanceUSDC = ERC20(usdc).balanceOf(address(exit10));
    uint256 balanceWETH = ERC20(weth).balanceOf(address(exit10));
    _title('TOKENS IN CONTRACT');
    console.log(_displayAmount('Amount', usdc, balanceUSDC));
    console.log(_displayAmount('Amount', weth, balanceWETH));
    _spacer();
  }

  function _displayBuckets() internal view {
    (uint256 pending, uint256 reserve, uint256 exitBucket, uint256 bootstrap) = exit10.getBuckets();
    _title('BUCKETS BREAKDOWN');
    console.log('Pending Bucket: ', pending);
    console.log('Reserve Bucket: ', reserve);
    console.log('Exit Bucket: ', exitBucket);
    console.log('Bootstrap Bucket: ', bootstrap);
    _spacer();
  }

  function _displayAmount(
    string memory _targetTitle,
    address _token,
    uint256 _amount
  ) internal view returns (string memory) {
    string memory log0 = string.concat(
      _targetTitle,
      ' ',
      ERC20(_token).symbol(),
      ': ',
      _displayInDecimals(_token, _amount)
    );
    return log0;
  }

  function _displayBalance(string memory _targetTitle, address _target, address _token) internal view {
    string memory log0 = string.concat(
      _targetTitle,
      ' ',
      ERC20(_token).symbol(),
      ': ',
      _displayInDecimals(_token, ERC20(_token).balanceOf(_target))
    );
    console.log(log0);
  }

  function _displayBalances(
    string memory _targetTitle,
    address _target,
    address _tokenA,
    address _tokenB
  ) internal view {
    _displayBalance(_targetTitle, _target, _tokenA);
    _displayBalance(_targetTitle, _target, _tokenB);
  }

  function _displayInDecimals(address _token, uint256 _amount) internal view returns (string memory) {
    if (showAsInteger) {
      return Strings.toString(_amount);
    }

    return DecimalStrings.decimalString(_amount, ERC20(_token).decimals(), false);
  }

  function _displayTotal(string memory _titleText, uint256 _amountUSDC, uint256 _amountWETH) internal view {
    _title(_titleText);
    console.log(_displayAmount('Deposited', usdc, _amountUSDC));
    console.log(_displayAmount('Deposited', weth, _amountWETH));
    _spacer();
  }

  function _title(string memory _titleText) internal view {
    console.log(string.concat('-----', _titleText, '-----'));
  }

  function _spacer() internal view {
    console.log('----------------------------------');
  }
}
