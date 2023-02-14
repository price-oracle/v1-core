// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.4 <0.9.0;

import '@interfaces/IPoolManager.sol';
import '@interfaces/IPoolManagerFactory.sol';
import '@interfaces/jobs/IKeep3rJob.sol';

/**
  @notice Runs the job handling the position burning in WETH/TOKEN pools
 */
interface IPositionBurnerJob is IKeep3rJob {
  /*///////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Emitted when a position was burned
    @param _lockManager The address of the lock manager holding the position
    @param _position The burned position
   */
  event Worked(ILockManager _lockManager, IStrategy.Position _position);

  /*///////////////////////////////////////////////////////////////
                              ERRORS
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Thrown when we can't verify the pool manager
    @param _poolManager The pool manager in question
   */
  error PositionBurnerJob_InvalidPoolManager(IPoolManager _poolManager);

  /*///////////////////////////////////////////////////////////////
                            VARIABLES
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Returns the pool manager factory
    @return _poolManagerFactory The pool manager factory
   */
  function POOL_MANAGER_FACTORY() external view returns (IPoolManagerFactory _poolManagerFactory);

  /*///////////////////////////////////////////////////////////////
                              LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Burn the position in the lock manager and reward the keeper for doing so
    @dev    Will revert if the job is paused or if the keeper is not valid
    @param  _poolManager The address of the target pool manager
    @param  _position  The position to be burned
   */
  function work(IPoolManager _poolManager, IStrategy.Position memory _position) external;

  /**
    @notice Return true if the specified position can be burned
    @param  _poolManager The address of the target pool manager
    @param  _position The position to burn
    @return _workable True if the position can be burned
   */
  function isWorkable(IPoolManager _poolManager, IStrategy.Position memory _position) external returns (bool _workable);

  /**
    @notice Return true if the specified pool manager can be worked by the specified keeper
    @param  _poolManager The address of the target pool manager
    @param  _position The position to burn
    @param  _keeper The address of the keeper
    @return _workable True if the position can be burned
   */
  function isWorkable(
    IPoolManager _poolManager,
    IStrategy.Position memory _position,
    address _keeper
  ) external returns (bool _workable);
}
