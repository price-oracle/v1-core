// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '@test/e2e/Common.sol';
import '@contracts/jobs/PositionMinterJob.sol';

contract E2EPositionMinterJob is CommonE2EBase {
  PositionMinterJob positionMinterJob;
  IPoolManager poolManager;
  IUniswapV3Pool pool;

  function setUp() public override {
    super.setUp();

    // Initialize job
    positionMinterJob = new PositionMinterJob(poolManagerFactory, governance);
    label(address(positionMinterJob), 'PositionMinterJob');

    // Approve and fund the job
    _setUpJob(positionMinterJob);

    poolManager = lockManager.POOL_MANAGER();
    pool = poolManager.POOL();
  }

  function testE2EMintPosition() public {
    // Deposit WETH
    uint256 _mintAmount = strategy.MIN_WETH_TO_MINT();
    uint256 _lockAmount = (_mintAmount * 100) / strategy.PERCENT_WETH_TO_MINT();
    deal(address(weth), user1, _lockAmount);
    _lockWeth(user1, _lockAmount);

    // Cache balances to compare later
    uint256 _poolWethBalance = weth.balanceOf(address(pool));
    uint256 _lockManagerWethBalance = weth.balanceOf(address(lockManager));

    (, uint256 _totalWeth, uint256 _totalToken) = lockManager.withdrawalData();

    assertEq(_totalWeth, _lockAmount);
    assertEq(_totalToken, 0);

    // Mint a position
    vm.prank(keeper);
    positionMinterJob.work(poolManager);

    // Should update withdrawal data
    (, uint256 _totalWethAfter, uint256 _totalTokenAfter) = lockManager.withdrawalData();
    assertApproxEqAbs(_totalWethAfter, _totalWeth - _mintAmount, 0.02 ether);
    assertEq(_totalTokenAfter, 0);

    // Should transfer WETH to the pool
    assertApproxEqAbs(weth.balanceOf(address(lockManager)), _lockManagerWethBalance - _mintAmount, 0.02 ether);
    assertApproxEqAbs(weth.balanceOf(address(pool)), _poolWethBalance + _mintAmount, 0.02 ether);
  }
}
