// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '@test/e2e/Common.sol';
import '@contracts/jobs/FeeCollectorJob.sol';

contract E2EPoolManagerCollectFullRangeFees is CommonE2EBase {
  IPoolManager _poolManager;
  IFeeManager _feeManager;
  IUniswapV3Pool _pool;
  IERC20 _token;

  uint256 private constant _SWAP_SIZE = 1000 ether;
  uint256 private constant _NUMBER_OF_SWAPS = 250;

  uint256 private constant _DISTRIBUTION_BASE = 100_000;
  uint256 private constant _TAX_PERCENTAGE = 50_000;

  function setUp() public override {
    super.setUp();

    _poolManager = lockManager.POOL_MANAGER();
    _feeManager = _poolManager.feeManager();
    _pool = _poolManager.POOL();
    _token = _poolManager.TOKEN();

    // Deploy the job
    feeCollectorJob = new FeeCollectorJob(poolManagerFactory, governance);
    label(address(feeCollectorJob), 'FeeCollectorJob');

    vm.prank(governance);
    poolManagerFactory.setFeeCollectorJob(feeCollectorJob);

    // Register the job and add credits
    _setUpJob(feeCollectorJob);

    // Make swaps in the pool
    vm.startPrank(user1);
    _performMultipleSwaps(weth, _token, _SWAP_SIZE, _NUMBER_OF_SWAPS);

    // Approve the pool manager to increase full-range position
    _token.approve(address(_poolManager), type(uint256).max);
    weth.approve(address(_poolManager), type(uint256).max);

    _token.approve(address(_pool), type(uint256).max);
    weth.approve(address(_pool), type(uint256).max);

    _token.approve(address(uniswapRouter), type(uint256).max);
    weth.approve(address(uniswapRouter), type(uint256).max);

    vm.stopPrank();
  }

  function testCollectFeesForJob() public {
    _burn();

    // Figure the amount of owed fees in WETH and the other token
    (uint256 _wethOwed, uint256 _tokenOwed) = _owedAmounts();

    // Cache the fee manager state before working the job
    uint256 tokenBalanceBefore = _token.balanceOf(address(_feeManager));
    uint256 wethBalanceBefore = weth.balanceOf(address(_feeManager));

    // Run the job
    vm.prank(keeper);
    feeCollectorJob.work(_poolManager);

    // Calculate expected values
    (_wethOwed, _tokenOwed) = _feesAfterTaxes(_wethOwed, _tokenOwed);

    // The fee manager balance should include all fees from the pool, except for taxes and the governance part
    uint256 tokenBalanceAfter = _token.balanceOf(address(_feeManager));
    uint256 wethBalanceAfter = weth.balanceOf(address(_feeManager));

    assertApproxEqAbs(wethBalanceAfter, wethBalanceBefore + _wethOwed, DELTA);
    assertApproxEqAbs(tokenBalanceAfter, tokenBalanceBefore + _tokenOwed, DELTA);

    // Working the job when there is 0 fees in the pool should revert
    vm.expectRevert(GasCheckLib.GasCheckLib_InsufficientFees.selector);
    vm.prank(keeper);
    feeCollectorJob.work(_poolManager);

    // Should revert if there is a little amount of fees in the pool
    vm.startPrank(user1);
    _performMultipleSwaps(weth, _token, 1, 1);
    vm.stopPrank();

    vm.expectRevert(GasCheckLib.GasCheckLib_InsufficientFees.selector);
    vm.prank(keeper);
    feeCollectorJob.work(_poolManager);
  }

  function testCollectFees() public {
    _burn();
    vm.startPrank(governance);
    // Figure the amount of owed fees in WETH and the other token
    (uint256 _wethOwed, uint256 _tokenOwed) = _owedAmounts();

    // Cache the fee manager state before working the job
    uint256 tokenBalanceBefore = _token.balanceOf(address(_feeManager));
    uint256 wethBalanceBefore = weth.balanceOf(address(_feeManager));

    // Collect the fees
    _poolManager.collectFees();

    // Calculate expected values
    (_wethOwed, _tokenOwed) = _feesAfterTaxes(_wethOwed, _tokenOwed);

    // The fee manager balance should include all fees from the pool, except for taxes and the governance part
    uint256 tokenBalanceAfter = _token.balanceOf(address(_feeManager));
    uint256 wethBalanceAfter = weth.balanceOf(address(_feeManager));

    assertApproxEqAbs(wethBalanceAfter, wethBalanceBefore + _wethOwed, DELTA);
    assertApproxEqAbs(tokenBalanceAfter, tokenBalanceBefore + _tokenOwed, DELTA);

    // Should not revert when there is 0 fees in the pool
    _poolManager.collectFees();

    // Should not revert when there is a little amount of fees in the pool
    _performMultipleSwaps(weth, _token, _SWAP_SIZE, _NUMBER_OF_SWAPS);
    _poolManager.collectFees();

    vm.stopPrank();
  }

  /// @notice Calculates the part of the fees that should stay in the FeeManager
  /// @param _wethOwed The WETH fees to subtract the taxes from
  /// @param _tokenOwed The token fees to subtract the taxes from
  /// @return _wethAfterTaxes The amount of WETH fees minus taxes and the governance part
  /// @return _tokenAfterTaxes The amount of token fees minus taxes
  function _feesAfterTaxes(uint256 _wethOwed, uint256 _tokenOwed) internal view returns (uint256 _wethAfterTaxes, uint256 _tokenAfterTaxes) {
    _wethAfterTaxes = _wethOwed;
    _tokenAfterTaxes = _tokenOwed;

    // Subtracting taxes
    _wethAfterTaxes -= PRBMath.mulDiv(_wethAfterTaxes, _TAX_PERCENTAGE, _DISTRIBUTION_BASE);
    _tokenAfterTaxes -= PRBMath.mulDiv(_tokenAfterTaxes, _TAX_PERCENTAGE, _DISTRIBUTION_BASE);

    // Subtract the part of the fees dedicated to increasing cardinality and maintenance
    (uint256 _wethForCardinality, uint256 wethForMaintenance, ) = _feeManager.poolDistribution(_poolManager);
    _wethAfterTaxes -= PRBMath.mulDiv(_wethAfterTaxes, _wethForCardinality + wethForMaintenance, _DISTRIBUTION_BASE);
  }

  /// @notice Retrieves amount of available fees from the pool
  /// @return _wethOwed The available WETH fees
  /// @return _tokenOwed The available token fees
  function _owedAmounts() internal view returns (uint256 _wethOwed, uint256 _tokenOwed) {
    int24 _tickUpper = MAX_TICK - (MAX_TICK % _pool.tickSpacing());
    int24 _tickLower = -_tickUpper;
    if (_pool.token0() == address(weth)) {
      (, , , _wethOwed, _tokenOwed) = _pool.positions(keccak256(abi.encodePacked(address(_poolManager), _tickLower, _tickUpper)));
    } else {
      (, , , _tokenOwed, _wethOwed) = _pool.positions(keccak256(abi.encodePacked(address(_poolManager), _tickLower, _tickUpper)));
    }
  }

  function _burn() internal {
    int24 _tickUpper = MAX_TICK - (MAX_TICK % _pool.tickSpacing());
    int24 _tickLower = -_tickUpper;
    vm.prank(address(_poolManager));
    _pool.burn(_tickLower, _tickUpper, 0);
  }
}
