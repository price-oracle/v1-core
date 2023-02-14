// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.4 <0.9.0;

import 'uni-v3-core/interfaces/IUniswapV3Pool.sol';
import '@interfaces/IPoolManager.sol';

interface IStrategy {
  /*///////////////////////////////////////////////////////////////
                              STRUCTS
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Lock manager variables needed for the strategy
    @param poolManager The address of the pool manager
    @param pool The address of the UniswapV3 pool
    @param availableWeth The total amount of WETH available for minting into the pool
    @param isWethToken0 If WETH is token 0 in the pool
    @param tickSpacing The tick spacing in the pool
   */
  struct LockManagerState {
    IPoolManager poolManager;
    IUniswapV3Pool pool;
    uint256 availableWeth;
    bool isWethToken0;
    int24 tickSpacing;
  }

  /**
    @notice UniswapV3 pool position
    @param  lowerTick The lower tick of the position
    @param  upperTick The upper tick of the position
   */
  struct Position {
    int24 lowerTick;
    int24 upperTick;
  }

  /**
    @notice UniswapV3 pool position with the amount of liquidity
    @param  lowerTick The lower tick of the position
    @param  upperTick The upper tick of the position
    @param  liquidity The amount of liquidity in the position
   */
  struct LiquidityPosition {
    int24 lowerTick;
    int24 upperTick;
    uint128 liquidity;
  }

  /*///////////////////////////////////////////////////////////////
                              ERRORS
  //////////////////////////////////////////////////////////////*/
  /**
    @notice Thrown when the price oracle detects a manipulation
   */
  error Strategy_PoolManipulated();

  /**
    @notice Thrown when minting a position requires more WETH than available in the lock manager
   */
  error Strategy_NotEnoughWeth();

  /**
    @notice Thrown when the position to burn is too close to the current tick
   */
  error Strategy_NotFarEnoughToLeft();

  /**
    @notice Thrown when the position to burn is too close to the current tick
   */
  error Strategy_NotFarEnoughToRight();

  /*///////////////////////////////////////////////////////////////
                            VARIABLES
  //////////////////////////////////////////////////////////////*/
  /**
    @notice The minimum amount of WETH that can be minted into a new position
    @dev Remember safe deployment for min width is 1 ETH these amounts are already considering the 1/2 minting
    @return _minWethToMint The minimum amount of WETH that can be minted into a new position
   */
  function MIN_WETH_TO_MINT() external view returns (uint256 _minWethToMint);

  /**
    @notice The maximum amount of WETH that can be minted into a new position
    @return _maxWethToMint The maximum amount of WETH that can be minted into a new position
   */
  function MAX_WETH_TO_MINT() external view returns (uint256 _maxWethToMint);

  /**
    @notice 50% of idle WETH per mint is used
    @return _percentWethToMint What percentage of idle WETH to use for minting
   */
  function PERCENT_WETH_TO_MINT() external view returns (uint256 _percentWethToMint);

  /**
    @notice How far to the right from the current tick a position should be in order to be burned
    @return _lowerBurnDiff The tick difference
   */
  function LOWER_BURN_DIFF() external view returns (int24 _lowerBurnDiff);

  /**
    @notice How far to the left from the current tick a position should be in order to be burned
    @return _upperBurnDiff The tick difference
   */
  function UPPER_BURN_DIFF() external view returns (int24 _upperBurnDiff);

  /**
    @notice The top of the safe range for volatility
    @return _volatilitySafeRangeMin
   */
  function VOLATILITY_SAFE_RANGE_MIN() external view returns (uint256 _volatilitySafeRangeMin);

  /**
    @notice The bottom of the safe range for volatility
    @return _volatilitySafeRangeMax
   */
  function VOLATILITY_SAFE_RANGE_MAX() external view returns (uint256 _volatilitySafeRangeMax);

  /*///////////////////////////////////////////////////////////////
                            LOGIC
  //////////////////////////////////////////////////////////////*/
  /**
    @notice Returns the next position to mint
    @return _positionToMint The position
   */
  function getPositionToMint(IStrategy.LockManagerState calldata _lockManagerState)
    external
    view
    returns (IStrategy.LiquidityPosition memory _positionToMint);

  /**
    @notice Returns the next position to burn
    @param  _position The position to burn, without liquidity
    @param  _positionLiquidity The liquidity in the position
    @return _positionToBurn The position to burn, with liquidity
   */
  function getPositionToBurn(
    IStrategy.Position calldata _position,
    uint128 _positionLiquidity,
    IStrategy.LockManagerState calldata _lockManagerState
  ) external view returns (IStrategy.LiquidityPosition memory _positionToBurn);
}
