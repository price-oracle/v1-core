// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import '@contracts/utils/PRBMath.sol';

/// @title Liquidity amount functions modified to be compatible with solidity 0.8
/// @notice Provides functions for computing liquidity amounts from token amounts and prices
/// @author Uniswap Labs in v3-periphery (https://github.com/Uniswap/v3-periphery/blob/main/contracts/libraries/LiquidityAmounts.sol)
library LiquidityAmounts08 {
  uint8 internal constant RESOLUTION = 96;
  uint256 internal constant Q96 = 0x1000000000000000000000000;

  /// @notice Computes the amount of token0 for a given amount of liquidity and a price range
  /// @param sqrtRatioAX96 A sqrt price representing the first tick boundary
  /// @param sqrtRatioBX96 A sqrt price representing the second tick boundary
  /// @param liquidity The liquidity being valued
  /// @return amount0 The amount of token0
  function getAmount0ForLiquidity(
    uint160 sqrtRatioAX96,
    uint160 sqrtRatioBX96,
    uint128 liquidity
  ) internal pure returns (uint256 amount0) {
    if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);
    return PRBMath.mulDiv(uint256(liquidity) << RESOLUTION, sqrtRatioBX96 - sqrtRatioAX96, sqrtRatioBX96) / sqrtRatioAX96;
  }

  /// @notice Computes the amount of token1 for a given amount of liquidity and a price range
  /// @param sqrtRatioAX96 A sqrt price representing the first tick boundary
  /// @param sqrtRatioBX96 A sqrt price representing the second tick boundary
  /// @param liquidity The liquidity being valued
  /// @return amount1 The amount of token1
  function getAmount1ForLiquidity(
    uint160 sqrtRatioAX96,
    uint160 sqrtRatioBX96,
    uint128 liquidity
  ) internal pure returns (uint256 amount1) {
    if (sqrtRatioAX96 > sqrtRatioBX96) (sqrtRatioAX96, sqrtRatioBX96) = (sqrtRatioBX96, sqrtRatioAX96);

    return PRBMath.mulDiv(liquidity, sqrtRatioBX96 - sqrtRatioAX96, Q96);
  }
}
