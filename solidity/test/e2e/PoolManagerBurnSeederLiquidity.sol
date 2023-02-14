// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '@test/e2e/Common.sol';

contract E2EPoolManagerBurnSeederLiquidity is CommonE2EBase {
  IPoolManager _poolManager;
  IFeeManager _feeManager;
  IUniswapV3Pool _pool;
  IERC20 _token;

  uint256 private constant _SWAP_SIZE = 50 ether;
  uint256 private constant _NUMBER_OF_SWAPS = 150;

  function setUp() public override {
    super.setUp();

    _poolManager = lockManager.POOL_MANAGER();
    _feeManager = _poolManager.feeManager();
    _pool = _poolManager.POOL();
    _token = _poolManager.TOKEN();

    // Make swaps in the pool
    vm.startPrank(user1);
    _performMultipleSwaps(weth, _token, _SWAP_SIZE, _NUMBER_OF_SWAPS);

    // Approve the pool manager to increase full-range position
    _token.approve(address(_poolManager), type(uint256).max);
    weth.approve(address(_poolManager), type(uint256).max);

    vm.stopPrank();
  }

  function testBurnAndCheckFees() public {
    (uint160 _sqrtPriceX96, , , , , , ) = _pool.slot0();

    // User1 Increases the full range
    vm.prank(user1);
    _poolManager.increaseFullRangePosition(user1, 100 ether, _sqrtPriceX96);

    // Collect the fees
    vm.prank(governance);
    _poolManager.collectFees();

    // Gets Liquidity seeded
    uint256 _seededLiquidity = _poolManager.poolLiquidity();
    uint256 _seederBalance = _poolManager.seederBalance(user1);

    // Burn some liquidity
    vm.startPrank(user1);
    _poolManager.burn(_seederBalance);

    // Seeded Liquidity should be the same
    assertEq(_poolManager.poolLiquidity(), _seededLiquidity);

    // Seeder balance has to be decreased
    assertEq(_poolManager.seederBalance(user1), 0);

    // Store the claimable amounts
    (uint256 claimableWeth, uint256 claimableToken) = _poolManager.claimable(user1);
    _poolManager.claimRewards(user1);

    // User1 has rewards to claim
    assertGe(claimableWeth, 0);
    assertGe(claimableToken, 0);

    // Make swaps again in the pool
    _performMultipleSwaps(weth, _token, _SWAP_SIZE, _NUMBER_OF_SWAPS);
    vm.stopPrank();

    // Collect the fees
    vm.prank(governance);
    _poolManager.collectFees();

    // Store the new claimable amounts
    (uint256 newClaimableWeth, uint256 newClaimableToken) = _poolManager.claimable(user1);

    // Now user1 doesn't have any rewards to claim because he burned all liquidity
    assertEq(newClaimableWeth, 0);
    assertEq(newClaimableToken, 0);
  }
}
