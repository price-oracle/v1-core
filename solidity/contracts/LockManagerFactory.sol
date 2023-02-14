// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.4 <0.9.0;

import '@interfaces/ILockManagerFactory.sol';
import '@contracts/LockManager.sol';

contract LockManagerFactory is ILockManagerFactory {
  /// @inheritdoc ILockManagerFactory
  function createLockManager(IPoolManager.LockManagerParams calldata _lockManagerParams) external returns (ILockManager _lockManager) {
    _lockManager = new LockManager(IPoolManager(msg.sender), _lockManagerParams);
    emit LockManagerCreated(_lockManager);
  }
}
