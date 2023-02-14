// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.4 <0.9.0;

import '@interfaces/jobs/IFeeCollectorJob.sol';
import '@contracts/jobs/Keep3rJob.sol';

/**
  @notice Collects the fees from a list of positions
 */
contract FeeCollectorJob is IFeeCollectorJob, Keep3rJob {
  /// @inheritdoc IFeeCollectorJob
  IPoolManagerFactory public immutable POOL_MANAGER_FACTORY;
  /// @inheritdoc IFeeCollectorJob
  uint256 public collectMultiplier;

  /**
    @dev Payable constructor does not waste gas on checking msg.value
   */
  constructor(IPoolManagerFactory _poolManagerFactory, address _governor) payable Governable(_governor) {
    POOL_MANAGER_FACTORY = _poolManagerFactory;
    collectMultiplier = 20;
  }

  /// @inheritdoc IFeeCollectorJob
  function work(IPoolManager _poolManager, IStrategy.Position[] calldata _positions) external upkeep(msg.sender) notPaused {
    if (!POOL_MANAGER_FACTORY.isChild(_poolManager)) revert FeeCollectorJob_InvalidPoolManager(_poolManager);
    ILockManager _lockManager = _poolManager.lockManager();
    _lockManager.collectFees(_positions);
    emit WorkedLockManager(_lockManager, _positions);
  }

  /// @inheritdoc IFeeCollectorJob
  function work(IPoolManager _poolManager) external upkeep(msg.sender) notPaused {
    if (!POOL_MANAGER_FACTORY.isChild(_poolManager)) revert FeeCollectorJob_InvalidPoolManager(_poolManager);
    _poolManager.collectFees();
    emit WorkedPoolManager(_poolManager);
  }

  /// @inheritdoc IFeeCollectorJob
  function setCollectMultiplier(uint256 _collectMultiplier) external onlyGovernor {
    collectMultiplier = _collectMultiplier;
    emit CollectMultiplierSet(_collectMultiplier);
  }
}
