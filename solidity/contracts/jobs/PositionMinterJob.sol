// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.4 <0.9.0;

import '@contracts/jobs/Keep3rJob.sol';
import '@interfaces/jobs/IPositionMinterJob.sol';

contract PositionMinterJob is IPositionMinterJob, Keep3rJob {
  /// @inheritdoc IPositionMinterJob
  IPoolManagerFactory public immutable POOL_MANAGER_FACTORY;

  constructor(IPoolManagerFactory _poolManagerFactory, address _governor) payable Governable(_governor) {
    POOL_MANAGER_FACTORY = _poolManagerFactory;
  }

  /// @inheritdoc IPositionMinterJob
  function work(IPoolManager _poolManager) external upkeep(msg.sender) notPaused {
    if (!POOL_MANAGER_FACTORY.isChild(_poolManager)) revert PositionMinterJob_InvalidPoolManager(_poolManager);
    _poolManager.lockManager().mintPosition();
    emit Worked(_poolManager);
  }

  /// @inheritdoc IPositionMinterJob
  function isWorkable(IPoolManager _poolManager) external returns (bool _workable) {
    _workable = _isWorkable(_poolManager);
  }

  /// @inheritdoc IPositionMinterJob
  function isWorkable(IPoolManager _poolManager, address _keeper) external returns (bool _workable) {
    if (!_isValidKeeper(_keeper)) return false;
    _workable = _isWorkable(_poolManager);
  }

  /**
    @notice Returns true if the specified pool manager can be worked
    @param  _poolManager The address of the target pool manager
    @return _workable True if the pool manager can be worked
   */
  function _isWorkable(IPoolManager _poolManager) internal returns (bool _workable) {
    if (paused) return false;

    IStrategy.LiquidityPosition memory _positionToMint = _poolManager.lockManager().getPositionToMint();
    _workable = _positionToMint.liquidity > 0;
  }
}
