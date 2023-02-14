// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.4 <0.9.0;

import '@interfaces/jobs/ICardinalityJob.sol';
import '@contracts/jobs/Keep3rJob.sol';

/**
  @notice Runs the job handling the cardinality increase in WETH/TOKEN pools
 */
contract CardinalityJob is ICardinalityJob, Keep3rJob {
  /// @inheritdoc ICardinalityJob
  IPoolManagerFactory public poolManagerFactory;

  /// @inheritdoc ICardinalityJob
  uint16 public minCardinalityIncrease;

  /**
    @notice The maximum cardinality for a UniswapV3 pool
   */
  uint16 internal constant _MAX_CARDINALITY = 65535;

  /**
    @dev Payable constructor does not waste gas on checking msg.value
   */
  constructor(
    IPoolManagerFactory _poolManagerFactory,
    uint16 _minCardinalityIncrease,
    address _governor
  ) payable Governable(_governor) {
    poolManagerFactory = _poolManagerFactory;
    minCardinalityIncrease = _minCardinalityIncrease;
  }

  /// @inheritdoc ICardinalityJob
  function work(IPoolManager _poolManager, uint16 _increaseAmount) external upkeep(msg.sender) notPaused {
    uint256 _gasBefore = gasleft();
    if (_increaseAmount < getMinCardinalityIncreaseForPool(_poolManager)) revert CardinalityJob_MinCardinality();
    if (!poolManagerFactory.isChild(_poolManager)) revert CardinalityJob_InvalidPoolManager();
    IFeeManager _feeManager = _poolManager.feeManager();
    IUniswapV3Pool _pool = _poolManager.POOL();
    (, , , , uint16 _observationCardinalityNext, , ) = _pool.slot0();
    uint16 _newCardinality = _observationCardinalityNext + _increaseAmount;
    _pool.increaseObservationCardinalityNext(_newCardinality);
    _feeManager.increaseCardinality(_poolManager, (_gasBefore - gasleft()) * block.basefee, _newCardinality);
    emit Worked(_poolManager, _increaseAmount);
  }

  /// @inheritdoc ICardinalityJob
  function isWorkable(IPoolManager _poolManager, uint16 _increaseAmount) external view returns (bool _workable) {
    _workable = _isWorkable(_poolManager, _increaseAmount);
  }

  /// @inheritdoc ICardinalityJob
  function isWorkable(
    IPoolManager _poolManager,
    uint16 _increaseAmount,
    address _keeper
  ) external returns (bool _workable) {
    if (!_isValidKeeper(_keeper)) return false;
    _workable = _isWorkable(_poolManager, _increaseAmount);
  }

  /// @inheritdoc ICardinalityJob
  function setMinCardinalityIncrease(uint16 _minCardinalityIncrease) external onlyGovernor {
    minCardinalityIncrease = _minCardinalityIncrease;
    emit MinCardinalityIncreaseChanged(_minCardinalityIncrease);
  }

  /// @inheritdoc ICardinalityJob
  function setPoolManagerFactory(IPoolManagerFactory _poolManagerFactory) external onlyGovernor {
    poolManagerFactory = _poolManagerFactory;
    emit PoolManagerFactoryChanged(_poolManagerFactory);
  }

  /**
    @notice Checks if the job can be worked in the current block
    @param  _poolManager The pool manager of the pool for which the cardinality will be increased
    @param  _increaseAmount The increased amount of the pool cardinality
    @return _workable If the job is workable with the given inputs
   */
  function _isWorkable(IPoolManager _poolManager, uint16 _increaseAmount) internal view returns (bool _workable) {
    if (poolManagerFactory.isChild(_poolManager) && _increaseAmount >= getMinCardinalityIncreaseForPool(_poolManager)) {
      (, , , , uint16 _observationCardinalityNext, , ) = _poolManager.POOL().slot0();
      uint16 _newCardinality = _observationCardinalityNext + _increaseAmount;
      _workable = _MAX_CARDINALITY > _newCardinality;
    }
  }

  /// @inheritdoc ICardinalityJob
  function getMinCardinalityIncreaseForPool(IPoolManager _poolManager) public view returns (uint256 _minCardinalityIncrease) {
    (, , , , uint16 _observationCardinalityNext, , ) = _poolManager.POOL().slot0();
    uint256 _maxCardinalityForPool = _poolManager.feeManager().getMaxCardinalityForPool(_poolManager);

    if (minCardinalityIncrease < (_maxCardinalityForPool - _observationCardinalityNext)) {
      _minCardinalityIncrease = minCardinalityIncrease;
    } else {
      _minCardinalityIncrease = (_maxCardinalityForPool - _observationCardinalityNext);
    }
  }
}
