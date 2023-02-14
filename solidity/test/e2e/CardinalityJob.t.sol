// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '@test/e2e/Common.sol';
import '@contracts/jobs/CardinalityJob.sol';

contract E2ECardinalityJob is CommonE2EBase {
  CardinalityJob cardinalityJob;
  IPoolManager poolManager;
  uint16 minCardinalityIncrease = 50; // bigger the number, lower the delta for the keeper payment
  uint256 constant MAX_DIFFERENCE_PERCENT = 15; // 15%
  uint256 constant BASE = 100;

  function setUp() public override {
    super.setUp();

    // Initialize job
    cardinalityJob = new CardinalityJob(poolManagerFactory, minCardinalityIncrease, governance);
    label(address(cardinalityJob), 'CardinalityJob');

    // Allow the pool manager to spend FeeManager's WETH
    vm.prank(address(feeManager));
    weth.approve(address(lockManager), 5 ether);

    // Deposit some WETH to FeeManager and PoolManager (imitates collectFee call)
    vm.startPrank(user1);
    weth.transfer(address(feeManager), 5 ether);
    weth.transfer(address(lockManager), 5 ether);

    // Approve and deposit some DAI like the FeeManager would do
    dai.approve(address(cardinalityJob), userInitialDaiBalance);
    vm.stopPrank();

    // Increase the amount of WETH available for CardinalityJob
    vm.prank(address(lockManager));
    feeManager.depositFromLockManager(2 ether, 0);

    // Save the job in the FeeManager
    vm.prank(governance);
    feeManager.setCardinalityJob(cardinalityJob);

    // Approve and fund the job
    _setUpJob(cardinalityJob);

    // Common setup
    poolManager = lockManager.POOL_MANAGER();
  }

  function testCardinalityIncrease(uint16 increaseAmount) public {
    IUniswapV3Pool pool = poolManager.POOL();
    (, , , , uint16 cardinalityBeforeWork, , ) = pool.slot0();

    vm.assume(increaseAmount > minCardinalityIncrease);
    vm.assume(increaseAmount < feeManager.poolCardinalityMax() - minCardinalityIncrease);
    vm.assume(increaseAmount < feeManager.poolCardinalityMax() - cardinalityBeforeWork);

    // Record the amount of WETH in FeeManager
    (uint256 wethBefore, , ) = feeManager.poolCardinality(poolManager);

    // Work
    vm.prank(keeper);
    uint256 gasBefore = gasleft();
    cardinalityJob.work(poolManager, increaseAmount);
    uint256 gasSpent = (gasBefore - gasleft()) * block.basefee;

    (, , , , uint16 cardinalityAfterWork, , ) = pool.slot0();

    assertEq(cardinalityAfterWork - cardinalityBeforeWork, increaseAmount);

    // Compare the amount of WETH left in the FeeManager to its previous value
    (uint256 wethAfter, , ) = feeManager.poolCardinality(poolManager);

    // The subtracted amount of WETH should be within 5% of the quote
    assertApproxEqAbs(wethBefore - wethAfter, gasSpent, PRBMath.mulDiv(gasSpent, MAX_DIFFERENCE_PERCENT, BASE));
  }

  // The job can't be worked with increaseAmount that's too small
  function testNotWorkableWithTooSmallIncrease(uint16 increaseAmount) public {
    vm.assume(increaseAmount < minCardinalityIncrease);
    assertFalse(cardinalityJob.isWorkable(poolManager, increaseAmount));
  }

  // The job can't be worked with an invalid pool manager address
  function testNotWorkableWithInvalidPoolManager(uint16 increaseAmount) public {
    vm.assume(increaseAmount >= minCardinalityIncrease);
    vm.assume(increaseAmount < feeManager.poolCardinalityMax() - minCardinalityIncrease);
    IPoolManager _poolManager = IPoolManager(newAddress());
    assertFalse(cardinalityJob.isWorkable(_poolManager, increaseAmount));
  }
}
