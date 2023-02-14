// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.4 <0.9.0;

import '@contracts/jobs/Keep3rJob.sol';
import '@interfaces/jobs/ILiquidityIncreaserJob.sol';

/**
  @notice Runs the job that increases the full-range position for a given pool manager
 */
contract LiquidityIncreaserJob is ILiquidityIncreaserJob, Keep3rJob {
  /// @inheritdoc ILiquidityIncreaserJob
  IPoolManagerFactory public immutable POOL_MANAGER_FACTORY;

  /// @inheritdoc ILiquidityIncreaserJob
  IERC20 public immutable WETH;

  /// @inheritdoc ILiquidityIncreaserJob
  uint256 public minIncreaseWeth;

  /**
    @dev Payable constructor does not waste gas on checking msg.value
   */
  constructor(
    IPoolManagerFactory _poolManagerFactory,
    address _governor,
    IERC20 _weth
  ) payable Governable(_governor) {
    POOL_MANAGER_FACTORY = _poolManagerFactory;
    WETH = _weth;
    minIncreaseWeth = 1 ether;
  }

  /// @inheritdoc ILiquidityIncreaserJob
  function work(
    IPoolManager _poolManager,
    uint256 _wethAmount,
    uint256 _tokenAmount
  ) external upkeep(msg.sender) notPaused {
    if (!POOL_MANAGER_FACTORY.isChild(_poolManager)) revert LiquidityIncreaserJob_InvalidPoolManager();
    (uint256 _amountWeth, uint256 _amountToken) = _poolManager.increaseFullRangePosition(_wethAmount, _tokenAmount);
    uint256 _totalEth = _amountWeth + _quoteTokenToEth(_poolManager, _amountToken);
    if (_totalEth < minIncreaseWeth) revert LiquidityIncreaserJob_InsufficientIncrease();
    emit Worked(_poolManager, _amountWeth, _amountToken);
  }

  /// @inheritdoc ILiquidityIncreaserJob
  function isWorkable(IPoolManager _poolManager) external returns (bool _workable) {
    _workable = _isWorkable(_poolManager);
  }

  /// @inheritdoc ILiquidityIncreaserJob
  function isWorkable(IPoolManager _poolManager, address _keeper) external returns (bool _workable) {
    if (!_isValidKeeper(_keeper)) return false;
    _workable = _isWorkable(_poolManager);
  }

  /// @inheritdoc ILiquidityIncreaserJob
  function setMinIncreaseWeth(uint256 _minIncreaseWeth) external onlyGovernor {
    minIncreaseWeth = _minIncreaseWeth;
    emit MinIncreaseWethSet(_minIncreaseWeth);
  }

  /**
    @notice Returns true if the specified pool manager can be worked
    @param  _poolManager The address of the target pool manager
    @return _workable True if the pool manager can be worked
   */
  function _isWorkable(IPoolManager _poolManager) internal returns (bool _workable) {
    if (paused) return false;

    (uint256 _amountWeth, uint256 _amountToken) = _poolManager.feeManager().poolManagerDeposits(_poolManager);
    uint256 _totalEth = _amountWeth + _quoteTokenToEth(_poolManager, _amountToken);
    _workable = _totalEth > minIncreaseWeth;
  }

  /**
    @notice Quotes the given amount of token in ETH using the 10-minute TWAP
    @param  _poolManager The pool manager
    @param  _tokenAmount The token amount to convert
    @return _ethAmount The quote in ETH amount
   */
  function _quoteTokenToEth(IPoolManager _poolManager, uint256 _tokenAmount) internal returns (uint256 _ethAmount) {
    IPriceOracle _priceOracle = _poolManager.priceOracle();
    if (_priceOracle.isManipulated(_poolManager.POOL())) revert LiquidityIncreaserJob_PoolManipulated();
    uint32 _period = _priceOracle.MIN_CORRECTION_PERIOD();
    _ethAmount = _priceOracle.quoteCache(_tokenAmount, _poolManager.TOKEN(), WETH, _period, uint24(_period));
  }
}
