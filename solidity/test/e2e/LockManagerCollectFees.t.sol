// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '@test/e2e/Common.sol';
import '@contracts/jobs/FeeCollectorJob.sol';

contract E2ELockManagerCollectFees is CommonE2EBase {
  uint256 user1LockAmount = 50 ether;
  uint256 private constant _SWAP_SIZE = 100_000 * 1e18;
  uint256 private constant _NUMBER_OF_SWAPS = 500;

  IPoolManager _poolManager;
  IFeeManager _feeManager;
  IUniswapV3Pool _pool;
  IERC20 _token;
  address _maintenance;
  IStrategy.Position[] _positions;

  function setUp() public override {
    super.setUp();

    _poolManager = lockManager.POOL_MANAGER();
    _feeManager = _poolManager.feeManager();
    _pool = _poolManager.POOL();
    _token = _poolManager.TOKEN();
    _maintenance = _feeManager.maintenanceGovernance();

    // Deposit WETH and a position
    _lockWeth(user1, user1LockAmount);
    lockManager.mintPosition();

    // Get the only minted position
    uint256 _positionsCount = lockManager.getPositionsCount();
    IStrategy.LiquidityPosition[] memory _createdPositions = lockManager.positionsList(0, _positionsCount);
    for (uint256 _index; _index < _positionsCount; _index++) {
      _positions.push(IStrategy.Position(_createdPositions[_index].lowerTick, _createdPositions[_index].upperTick));
    }

    (uint256 wethPerLockedWeth, uint256 tokenPerLockedWeth) = lockManager.poolRewards();

    // No swaps so rewards should still be 0
    assertEq(wethPerLockedWeth + tokenPerLockedWeth, 0);
    assertEq(weth.balanceOf(address(_feeManager)) + _token.balanceOf(address(_feeManager)), 0);

    // Approve the Uniswap router to allow swaps
    vm.startPrank(user1);
    weth.approve(address(uniswapRouter), type(uint256).max);
    _token.approve(address(uniswapRouter), type(uint256).max);

    // Trade from DAI to WETH and back within the position created earlier
    _performMultipleSwaps(_token, weth, _SWAP_SIZE, _NUMBER_OF_SWAPS);
    vm.stopPrank();

    // Set up FeeCollectorJob
    feeCollectorJob = new FeeCollectorJob(poolManagerFactory, governance);
    label(address(feeCollectorJob), 'FeeCollectorJob');

    vm.prank(governance);
    poolManagerFactory.setFeeCollectorJob(feeCollectorJob);

    _setUpJob(feeCollectorJob);
  }

  function testE2ECollectFees() public {
    uint256 lockManagerWethBalanceBefore = weth.balanceOf(address(lockManager));
    uint256 lockManagerTokenBalanceBefore = _token.balanceOf(address(lockManager));

    uint256 feeManagerWethBalanceBefore = weth.balanceOf(address(_feeManager)) + weth.balanceOf(_maintenance);
    uint256 feeManagerTokenBalanceBefore = _token.balanceOf(address(_feeManager)) + _token.balanceOf(_maintenance);

    lockManager.collectFees(_positions);

    {
      //Rewards should not be 0 now!
      (uint256 wethPerLockedWeth, uint256 tokenPerLockedWeth) = lockManager.poolRewards();
      assertGt(wethPerLockedWeth, 0);
      assertGt(tokenPerLockedWeth, 0);
    }

    uint256 feeManagerWethBalance = weth.balanceOf(address(_feeManager)) + weth.balanceOf(_maintenance);
    uint256 feeManagerTokenBalance = _token.balanceOf(address(_feeManager)) + _token.balanceOf(_maintenance);

    assertGt(feeManagerWethBalance, 0);
    assertGt(feeManagerTokenBalance, 0);

    uint256 lockManagerWethBalanceAfter = weth.balanceOf(address(lockManager));
    uint256 lockManagerTokenBalanceAfter = _token.balanceOf(address(lockManager));

    // Lock manager should have 4x the amount sent to the fee manager
    assertApproxEqAbs(
      lockManagerWethBalanceAfter - lockManagerWethBalanceBefore,
      (feeManagerWethBalance - feeManagerWethBalanceBefore) * 4,
      DELTA
    );
    assertApproxEqAbs(
      lockManagerTokenBalanceAfter - lockManagerTokenBalanceBefore,
      (feeManagerTokenBalance - feeManagerTokenBalanceBefore) * 4,
      DELTA
    );
  }

  function testE2ECollectFeesForJob() public {
    uint256 lockManagerWethBalanceBefore = weth.balanceOf(address(lockManager));
    uint256 lockManagerTokenBalanceBefore = _token.balanceOf(address(lockManager));

    uint256 feeManagerWethBalanceBefore = weth.balanceOf(address(_feeManager)) + weth.balanceOf(_maintenance);
    uint256 feeManagerTokenBalanceBefore = _token.balanceOf(address(_feeManager)) + _token.balanceOf(_maintenance);

    vm.prank(keeper);
    feeCollectorJob.work(_poolManager, _positions);

    {
      // Rewards should not be 0 now!
      (uint256 wethPerLockedWeth, uint256 tokenPerLockedWeth) = lockManager.poolRewards();

      assertGt(wethPerLockedWeth, 0);
      assertGt(tokenPerLockedWeth, 0);
    }

    uint256 feeManagerWethBalance = weth.balanceOf(address(_feeManager)) + weth.balanceOf(_maintenance);
    uint256 feeManagerTokenBalance = _token.balanceOf(address(_feeManager)) + _token.balanceOf(_maintenance);

    assertGt(feeManagerWethBalance, 0);
    assertGt(feeManagerTokenBalance, 0);

    uint256 lockManagerWethBalanceAfter = weth.balanceOf(address(lockManager));
    uint256 lockManagerTokenBalanceAfter = _token.balanceOf(address(lockManager));
    // Lock manager should have 4x the amount sent to the fee manager
    assertApproxEqAbs(
      lockManagerWethBalanceAfter - lockManagerWethBalanceBefore,
      (feeManagerWethBalance - feeManagerWethBalanceBefore) * 4,
      DELTA
    );
    assertApproxEqAbs(
      lockManagerTokenBalanceAfter - lockManagerTokenBalanceBefore,
      (feeManagerTokenBalance - feeManagerTokenBalanceBefore) * 4,
      DELTA
    );
  }

  function testE2ERevertIfSmallCollect() public {
    vm.prank(governance);
    feeCollectorJob.setCollectMultiplier(100_000);

    vm.expectRevert(GasCheckLib.GasCheckLib_InsufficientFees.selector);
    vm.prank(keeper);
    feeCollectorJob.work(_poolManager, _positions);
  }
}
