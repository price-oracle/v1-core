// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.4 <0.9.0;

import 'uni-v3-core/interfaces/IUniswapV3Pool.sol';
import '@interfaces/periphery/IPriceOracle.sol';
import '@contracts/utils/PRBMath.sol';

library GasCheckLib {
  /// @notice The amount of gas units spent on reading slot0
  uint256 internal constant SLOT0_GAS_USAGE = 6200;

  /**
    @notice Thrown when the price oracle detects a manipulation
   */
  error GasCheckLib_PoolManipulated();
  /**
    @notice Thrown when the sum of WETH and non-WETH fees does not cover the gas cost of collecting them
   */
  error GasCheckLib_InsufficientFees();

  /**
    @notice Collects the fees from the full-range position
    @dev    Burns zero liquidity in the given position to trigger fees calculation
    @param  _pool The UniswapV3 pool
    @param  _priceOracle The price oracle
    @param  _collectMultiplier The multiplier used to overestimate the gas spending
    @param  _lowerTick The lower tick of the position
    @param  _upperTick The upper tick of the position
    @param  _isWethToken0 If WETH is token0 in the pool
    @return _amount0 The collected fees for token0
    @return _amount1 The collected fees for token1
   */
  function collectFromFullRangePosition(
    IUniswapV3Pool _pool,
    IPriceOracle _priceOracle,
    uint256 _collectMultiplier,
    int24 _lowerTick,
    int24 _upperTick,
    bool _isWethToken0
  ) internal returns (uint256 _amount0, uint256 _amount1) {
    // Find the gas expenditure for the oracle and pool calls
    uint256 _collectGasCost = gasleft();
    if (_priceOracle.isManipulated(_pool)) revert GasCheckLib_PoolManipulated();
    _pool.burn(_lowerTick, _upperTick, 0);
    (_amount0, _amount1) = _pool.collect(address(this), _lowerTick, _upperTick, type(uint128).max, type(uint128).max);
    (uint160 _sqrtPriceX96, , , , , , ) = _pool.slot0();
    _collectGasCost -= gasleft();

    quoteAndCompare(_amount0, _amount1, _sqrtPriceX96, _collectGasCost, _collectMultiplier, _isWethToken0);
  }

  /**
    @notice Collects the fees from a concentrated position
    @dev    Burns zero liquidity in the given position to trigger fees calculation
    @param  _pool The UniswapV3 pool
    @param  _sqrtPriceX96 The current sqrt price in the pool
    @param  _collectMultiplier The multiplier used to overestimate the gas spending
    @param  _slot0CostPerPosition The amount of gas spent calling the slot0 divided by the number of positions
    @param  _lowerTick The lower tick of the position
    @param  _upperTick The upper tick of the position
    @param  _isWethToken0 If WETH is token0 in the pool
    @return _amount0 The collected fees for token0
    @return _amount1 The collected fees for token1
   */
  function collectFromConcentratedPosition(
    IUniswapV3Pool _pool,
    uint160 _sqrtPriceX96,
    uint256 _collectMultiplier,
    uint256 _slot0CostPerPosition,
    int24 _lowerTick,
    int24 _upperTick,
    bool _isWethToken0
  ) internal returns (uint256 _amount0, uint256 _amount1) {
    // Find the gas expenditure for the pool calls
    uint256 _collectGasCost = gasleft();
    _pool.burn(_lowerTick, _upperTick, 0);
    (_amount0, _amount1) = _pool.collect(address(this), _lowerTick, _upperTick, type(uint128).max, type(uint128).max);
    _collectGasCost -= gasleft();
    _collectGasCost += _slot0CostPerPosition;

    quoteAndCompare(_amount0, _amount1, _sqrtPriceX96, _collectGasCost, _collectMultiplier, _isWethToken0);
  }

  /**
    @notice Computes the total amount of fees in WETH and reverts if it does not justify the gas spending
    @dev    The math is a part of UniswapOracle, see `_getQuoteAtTick`
    @param  _amount0 The collected fees for token0
    @param  _amount1 The collected fees for token1
    @param  _sqrtPriceX96 The current sqrt price in the pool
    @param  _collectGasCost The amount of gas units spend on collecting the fees
    @param  _collectMultiplier The multiplier used to overestimate the gas spending
    @param  _isWethToken0 If WETH is the token0 in the pool
   */
  function quoteAndCompare(
    uint256 _amount0,
    uint256 _amount1,
    uint160 _sqrtPriceX96,
    uint256 _collectGasCost,
    uint256 _collectMultiplier,
    bool _isWethToken0
  ) internal view {
    // Calculate the amount of WETH spent on the external calls above
    uint256 _collectCostWeth = _collectGasCost * _collectMultiplier * block.basefee;

    // Convert the non-WETH fees to WETH using the current price ratio
    uint256 _ratioX128 = PRBMath.mulDiv(_sqrtPriceX96, _sqrtPriceX96, 1 << 64);
    uint256 _totalCollectedWeth = _isWethToken0
      ? PRBMath.mulDiv(1 << 128, _amount1, _ratioX128) + _amount0
      : PRBMath.mulDiv(_ratioX128, _amount0, 1 << 128) + _amount1;

    // Reverts if the collected amounts in ETH are less than the gas spent collecting them
    if (_collectCostWeth > _totalCollectedWeth) revert GasCheckLib_InsufficientFees();
  }
}
