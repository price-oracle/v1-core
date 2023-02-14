// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.4 <0.9.0;

import 'uni-v3-core/libraries/TickMath.sol';
import 'uni-v3-periphery/libraries/LiquidityAmounts.sol';
import 'isolmate/utils/FixedPointMathLib.sol';

import '@interfaces/strategies/IStrategy.sol';
import '@interfaces/periphery/IPriceOracle.sol';

contract Strategy is IStrategy {
  /// @inheritdoc IStrategy
  uint256 public constant MIN_WETH_TO_MINT = 10 ether;

  /// @inheritdoc IStrategy
  uint256 public constant MAX_WETH_TO_MINT = MIN_WETH_TO_MINT * 3;

  /// @inheritdoc IStrategy
  uint256 public constant PERCENT_WETH_TO_MINT = 50;

  /// @inheritdoc IStrategy
  uint256 public constant VOLATILITY_SAFE_RANGE_MIN = 1_200;

  /// @inheritdoc IStrategy
  uint256 public constant VOLATILITY_SAFE_RANGE_MAX = 1_500;

  /// @inheritdoc IStrategy
  int24 public constant LOWER_BURN_DIFF = 2231;

  /// @inheritdoc IStrategy
  int24 public constant UPPER_BURN_DIFF = 1823;

  /// @inheritdoc IStrategy
  function getPositionToMint(LockManagerState calldata _lockManagerState)
    external
    view
    virtual
    returns (LiquidityPosition memory _positionToMint)
  {
    int24 _tickSpacing = _lockManagerState.tickSpacing;
    (, int24 _currentTick, , , , , ) = _lockManagerState.pool.slot0();
    uint256 _totalWeth = _lockManagerState.availableWeth;
    uint256 _amount = FixedPointMathLib.mulDivDown(_totalWeth, PERCENT_WETH_TO_MINT, 100);

    if (_amount < MIN_WETH_TO_MINT) {
      if (_totalWeth > MIN_WETH_TO_MINT)
        _amount = _totalWeth; // use full amount (max 2xPERCENT_WETH_TO_MINT of MIN_WETH_TO_MINT)
      else revert Strategy_NotEnoughWeth();
    }

    int24 _upperTick;
    int24 _lowerTick;

    if (_lockManagerState.isWethToken0) {
      int24 _nextTick = _getNextTick(_currentTick, _tickSpacing);
      uint160 _nextSqrtWethX96 = TickMath.getSqrtRatioAtTick(_nextTick);
      uint160 _sqrtPUpperMinX96 = uint160(FixedPointMathLib.mulDivDown(_nextSqrtWethX96, VOLATILITY_SAFE_RANGE_MIN, 1_000));
      uint160 _sqrtPUpperMaxX96 = uint160(FixedPointMathLib.mulDivDown(_nextSqrtWethX96, VOLATILITY_SAFE_RANGE_MAX, 1_000));
      uint160 _sqrtPUpperX96;

      if (_amount > MAX_WETH_TO_MINT) {
        _amount = MAX_WETH_TO_MINT;
        _sqrtPUpperX96 = _sqrtPUpperMaxX96;
      } else {
        _sqrtPUpperX96 = uint160(
          ((_amount - MIN_WETH_TO_MINT) * (_sqrtPUpperMaxX96 - _sqrtPUpperMinX96)) / (MAX_WETH_TO_MINT - MIN_WETH_TO_MINT) + _sqrtPUpperMinX96
        );
      }
      _upperTick = _getNextTick(TickMath.getTickAtSqrtRatio(_sqrtPUpperX96), _tickSpacing);

      _positionToMint = LiquidityPosition({
        lowerTick: _nextTick, // int24
        upperTick: _upperTick, // int24
        liquidity: LiquidityAmounts.getLiquidityForAmount0(
          _nextSqrtWethX96, // uint160 lowest value first
          _sqrtPUpperX96, // uint160
          _amount // uint256
        ) // uint128
      });
    } else {
      // !_lockManagerState.isWethToken0
      int24 _previousTick = _getPreviousTick(_currentTick, _tickSpacing);
      uint160 _previousSqrtWethX96 = TickMath.getSqrtRatioAtTick(_previousTick);

      uint160 _sqrtPLowerMaxX96 = uint160(FixedPointMathLib.mulDivDown(_previousSqrtWethX96, 1_000, VOLATILITY_SAFE_RANGE_MIN));
      uint160 _sqrtPLowerMinX96 = uint160(FixedPointMathLib.mulDivDown(_previousSqrtWethX96, 1_000, VOLATILITY_SAFE_RANGE_MAX));
      uint160 _sqrtPLowerX96;

      if (_amount > MAX_WETH_TO_MINT) {
        _amount = MAX_WETH_TO_MINT;
        _sqrtPLowerX96 = _sqrtPLowerMinX96;
      } else {
        _sqrtPLowerX96 = uint160(
          ((_amount - MIN_WETH_TO_MINT) * (_sqrtPLowerMaxX96 - _sqrtPLowerMinX96)) / (MAX_WETH_TO_MINT - MIN_WETH_TO_MINT) + _sqrtPLowerMaxX96
        );
      }
      _lowerTick = _getPreviousTick(TickMath.getTickAtSqrtRatio(_sqrtPLowerX96), _tickSpacing);

      _positionToMint = LiquidityPosition({
        lowerTick: _lowerTick, // int24
        upperTick: _previousTick, // int24
        liquidity: LiquidityAmounts.getLiquidityForAmount1(
          _sqrtPLowerX96, // uint160 lowest value first
          _previousSqrtWethX96, // uint160
          _amount // uint256
        ) // uint128
      });
    }
  }

  /**
    @notice Returns the next tick in the pool
    @param  _tick The target tick
    @return _nextTick The first tick to the right of the target
   */
  function _getNextTick(int24 _tick, int24 _tickSpacing) internal pure returns (int24 _nextTick) {
    return _tick - (_tick % _tickSpacing) + _tickSpacing;
  }

  /**
    @notice Returns the previous tick in the pool
    @param  _tick The target tick
    @return _previousTick The first tick to the left of the target
   */
  function _getPreviousTick(int24 _tick, int24 _tickSpacing) internal pure returns (int24 _previousTick) {
    return _tick - (_tick % _tickSpacing);
  }

  /// @inheritdoc IStrategy
  function getPositionToBurn(
    Position calldata _position,
    uint128 _positionLiquidity,
    LockManagerState calldata _lockManagerState
  ) external view virtual returns (LiquidityPosition memory _positionToBurn) {
    (, int24 _currentTick, , , , , ) = _lockManagerState.pool.slot0();

    if (_lockManagerState.isWethToken0) {
      if (_position.lowerTick - LOWER_BURN_DIFF < _currentTick) revert Strategy_NotFarEnoughToRight();
    } else {
      if (_position.upperTick + UPPER_BURN_DIFF > _currentTick) revert Strategy_NotFarEnoughToLeft();
    }
    _positionToBurn = LiquidityPosition({lowerTick: _position.lowerTick, upperTick: _position.upperTick, liquidity: _positionLiquidity});
  }
}
