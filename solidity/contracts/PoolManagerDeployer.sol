// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.4 <0.9.0;

import '@interfaces/IPoolManagerDeployer.sol';
import '@contracts/PoolManager.sol';

contract PoolManagerDeployer is IPoolManagerDeployer {
  /// @inheritdoc IPoolManagerDeployer
  IPoolManagerFactory public immutable POOL_MANAGER_FACTORY;

  constructor(IPoolManagerFactory _poolManagerFactory) payable {
    POOL_MANAGER_FACTORY = _poolManagerFactory;
  }

  /// @inheritdoc IPoolManagerDeployer
  function deployPoolManager(IUniswapV3Pool _pool) external returns (IPoolManager _poolManager) {
    if (msg.sender != address(POOL_MANAGER_FACTORY)) revert PoolManagerDeployer_OnlyPoolManagerFactory();
    _poolManager = IPoolManager(new PoolManager{salt: keccak256(abi.encode(_pool))}());
  }
}
