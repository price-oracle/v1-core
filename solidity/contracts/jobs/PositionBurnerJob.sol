// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.4 <0.9.0;

import '@interfaces/jobs/IPositionBurnerJob.sol';
import '@contracts/jobs/Keep3rJob.sol';

contract PositionBurnerJob is IPositionBurnerJob, Keep3rJob {
  /// @inheritdoc IPositionBurnerJob
  IPoolManagerFactory public immutable POOL_MANAGER_FACTORY;

  constructor(IPoolManagerFactory _poolManagerFactory, address _governor) payable Governable(_governor) {
    POOL_MANAGER_FACTORY = _poolManagerFactory;
  }

  /// @inheritdoc IPositionBurnerJob
  function work(IPoolManager _poolManager, IStrategy.Position calldata _position) external upkeep(msg.sender) notPaused {
    if (!POOL_MANAGER_FACTORY.isChild(_poolManager)) revert PositionBurnerJob_InvalidPoolManager(_poolManager);
    ILockManager _lockManager = _poolManager.lockManager();
    _lockManager.burnPosition(_position);
    emit Worked(_lockManager, _position);
  }

  /// @inheritdoc IPositionBurnerJob
  function isWorkable(IPoolManager _poolManager, IStrategy.Position calldata _position) external returns (bool _workable) {
    _workable = _isWorkable(_poolManager, _position);
  }

  /// @inheritdoc IPositionBurnerJob
  function isWorkable(
    IPoolManager _poolManager,
    IStrategy.Position calldata _position,
    address _keeper
  ) external returns (bool _workable) {
    if (!_isValidKeeper(_keeper)) return false;
    _workable = _isWorkable(_poolManager, _position);
  }

  /**
    @notice Returns true if the specified pool manager can be worked
    @param  _poolManager The address of the target pool manager
    @param  _position The position to burn
    @return _workable True if the pool manager can be worked
   */
  function _isWorkable(IPoolManager _poolManager, IStrategy.Position calldata _position) internal returns (bool _workable) {
    if (paused) return false;

    IStrategy.LiquidityPosition memory _positionToBurn = _poolManager.lockManager().getPositionToBurn(_position);
    _workable = _positionToBurn.upperTick == _position.upperTick && _positionToBurn.lowerTick == _position.lowerTick;
  }
}
