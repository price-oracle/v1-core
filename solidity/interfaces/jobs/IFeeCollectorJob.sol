// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.4 <0.9.0;

import '@interfaces/IPoolManager.sol';
import '@interfaces/ILockManager.sol';
import '@interfaces/IPoolManagerFactory.sol';
import '@interfaces/jobs/IKeep3rJob.sol';

interface IFeeCollectorJob is IKeep3rJob {
  /*///////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Emitted when the job is worked
    @param  _lockManager The lock manager
    @param  _positions The list of positions to collect the fees from
   */
  event WorkedLockManager(ILockManager _lockManager, IStrategy.Position[] _positions);

  /**
    @notice Emitted when the job is worked
    @param  _poolManager The pool manager
   */
  event WorkedPoolManager(IPoolManager _poolManager);

  /**
    @notice Emitted when the collect multiplier has been set
    @param  _collectMultiplier The number of the multiplier
   */
  event CollectMultiplierSet(uint256 _collectMultiplier);

  /*///////////////////////////////////////////////////////////////
                              ERRORS
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Thrown when the pool manager cannot be verified
    @param  _poolManager The invalid pool manager
   */
  error FeeCollectorJob_InvalidPoolManager(IPoolManager _poolManager);

  /*///////////////////////////////////////////////////////////////
                            VARIABLES
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Returns the collect multiplier
    @return _collectMultiplier The collect multiplier
   */
  function collectMultiplier() external view returns (uint256 _collectMultiplier);

  /**
    @notice Returns the pool manager factory
    @return _poolManagerFactory The pool manager factory
   */
  function POOL_MANAGER_FACTORY() external view returns (IPoolManagerFactory _poolManagerFactory);

  /*///////////////////////////////////////////////////////////////
                              LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Collects the fees from the given positions and rewards the keeper
    @dev    Will revert if the job is paused or if the keeper is not valid
    @param  _poolManager The pool manager
    @param  _positions The list of positions to collect the fees from
   */
  function work(IPoolManager _poolManager, IStrategy.Position[] calldata _positions) external;

  /**
    @notice Collects the fees from the full range and rewards the keeper
    @dev    Will revert if the job is paused or if the keeper is not valid
    @param  _poolManager The pool manager
   */
  function work(IPoolManager _poolManager) external;

  /**
    @notice Sets the collect multiplier
    @dev    Only governance can change it
    @param  _collectMultiplier The collect multiplier
   */
  function setCollectMultiplier(uint256 _collectMultiplier) external;
}
