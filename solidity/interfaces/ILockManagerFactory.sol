// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.4 <0.9.0;

import '@interfaces/IPoolManager.sol';
import '@interfaces/ILockManager.sol';

interface ILockManagerFactory {
  /*///////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/
  /**
    @notice Emitted when the lock manager is created
    @param  _lockManager The lock manager that was created
   */
  event LockManagerCreated(ILockManager _lockManager);

  /*///////////////////////////////////////////////////////////////
                              LOGIC
  //////////////////////////////////////////////////////////////*/
  /**
    @notice Creates a lock manager
    @param  _lockManagerParams The parameters to initialize the lock manager
    @return _lockManager The created lock manager
   */
  function createLockManager(IPoolManager.LockManagerParams calldata _lockManagerParams) external returns (ILockManager _lockManager);
}
