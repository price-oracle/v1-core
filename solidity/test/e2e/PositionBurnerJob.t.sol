// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '@test/e2e/Common.sol';
import '@contracts/jobs/PositionBurnerJob.sol';

contract E2EPositionBurnerJob is CommonE2EBase {
  PositionBurnerJob positionBurnerJob;
  IPoolManager poolManager;
  IUniswapV3Pool pool;
  IERC20 token;
  IStrategy.Position _position;
  uint256 lockAmount = 50 ether;

  function setUp() public override {
    super.setUp();

    // Lock some WETH for the position
    _lockWeth(user1, lockAmount);

    // Create a position
    lockManager.mintPosition();

    // Initialize job
    positionBurnerJob = new PositionBurnerJob(poolManagerFactory, governance);
    label(address(positionBurnerJob), 'PositionBurnerJob');

    // Approve and fund the job
    _setUpJob(positionBurnerJob);

    poolManager = lockManager.POOL_MANAGER();
    pool = poolManager.POOL();
    token = poolManager.TOKEN();
  }

  function testE2EBurnPosition() public {
    (, uint256 _totalWeth, uint256 _totalToken) = lockManager.withdrawalData();

    // Move the current tick from the position
    vm.startPrank(user1);
    weth.approve(address(uniswapRouter), type(uint256).max);
    token.approve(address(uniswapRouter), type(uint256).max);

    // First trade the bulk of WETH then gradually trade more over several blocks to not trigger the manipulation check
    _swap(weth, token, 2000 ether);

    for (uint16 _i; _i < 55; _i++) {
      _swap(weth, token, 3 ether);
    }

    vm.stopPrank();

    // Burn a position
    IStrategy.LiquidityPosition memory _liquidityPosition = lockManager.positionsList(0, 1)[0];
    _position = IStrategy.Position({upperTick: _liquidityPosition.upperTick, lowerTick: _liquidityPosition.lowerTick});
    vm.prank(keeper);
    positionBurnerJob.work(poolManager, _position);

    // Should update withdrawal data
    (, uint256 _totalWethAfter, uint256 _totalTokenAfter) = lockManager.withdrawalData();

    // The trading activity fully converted token to WETH in the pool
    // When we burned the position, only WETH was returned
    // Hence the token amount stays the same and WETH amount increases
    assertTrue(_totalWethAfter > _totalWeth);
    assertEq(_totalTokenAfter, _totalToken);

    // Should transfer WETH from the pool back to the lock manager, along with trading fees
    assertEq(token.balanceOf(address(lockManager)), _totalTokenAfter);
    assertTrue(weth.balanceOf(address(lockManager)) >= _totalWethAfter);
  }
}
