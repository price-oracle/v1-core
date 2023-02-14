// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.4 <0.9.0;

import '@interfaces/jobs/ICorrectionsRemoverJob.sol';
import '@contracts/jobs/Keep3rJob.sol';

contract CorrectionsRemoverJob is ICorrectionsRemoverJob, Keep3rJob {
  /// @inheritdoc ICorrectionsRemoverJob
  IPoolManagerFactory public immutable POOL_MANAGER_FACTORY;

  /// @inheritdoc ICorrectionsRemoverJob
  IPriceOracle public immutable PRICE_ORACLE;

  constructor(IPoolManagerFactory _poolManagerFactory, address _governor) payable Governable(_governor) {
    POOL_MANAGER_FACTORY = _poolManagerFactory;
    PRICE_ORACLE = POOL_MANAGER_FACTORY.priceOracle();
  }

  /// @inheritdoc ICorrectionsRemoverJob
  function work(IUniswapV3Pool _pool) external upkeep(msg.sender) notPaused {
    if (!POOL_MANAGER_FACTORY.isSupportedPool(_pool)) revert CorrectionsRemoverJob_InvalidPool(_pool);
    PRICE_ORACLE.removeOldCorrections(_pool);
    emit Worked(_pool);
  }

  /// @inheritdoc ICorrectionsRemoverJob
  function isWorkable(IUniswapV3Pool _pool) external view returns (bool _workable) {
    _workable = _isWorkable(_pool);
  }

  /// @inheritdoc ICorrectionsRemoverJob
  function isWorkable(IUniswapV3Pool _pool, address _keeper) external returns (bool _workable) {
    _workable = _isValidKeeper(_keeper) && _isWorkable(_pool);
  }

  /**
    @notice Returns true if the oracle has old corrections for the specified pool
    @param _pool The Uniswap V3 pool
    @return _workable True if the pool can be worked
   */
  function _isWorkable(IUniswapV3Pool _pool) internal view returns (bool _workable) {
    if (POOL_MANAGER_FACTORY.isSupportedPool(_pool)) {
      uint256 _oldestCorrectionTimestamp = PRICE_ORACLE.getOldestCorrectionTimestamp(_pool);
      _workable = _oldestCorrectionTimestamp != 0 && _oldestCorrectionTimestamp > uint32(block.timestamp) - PRICE_ORACLE.MAX_CORRECTION_AGE();
    }
  }
}
