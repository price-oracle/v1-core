// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.4 <0.9.0;

import '@interfaces/jobs/ICorrectionsApplierJob.sol';
import '@contracts/jobs/Keep3rMeteredJob.sol';

contract CorrectionsApplierJob is ICorrectionsApplierJob, Keep3rMeteredJob {
  /// @inheritdoc ICorrectionsApplierJob
  IPoolManagerFactory public immutable POOL_MANAGER_FACTORY;

  /// @inheritdoc ICorrectionsApplierJob
  IPriceOracle public immutable PRICE_ORACLE;

  constructor(IPoolManagerFactory _poolManagerFactory, address _governor) payable Governable(_governor) {
    POOL_MANAGER_FACTORY = _poolManagerFactory;
    PRICE_ORACLE = POOL_MANAGER_FACTORY.priceOracle();
  }

  /// @inheritdoc ICorrectionsApplierJob
  function work(
    IUniswapV3Pool _pool,
    uint16 _manipulatedIndex,
    uint16 _period
  ) external upkeepMetered(msg.sender) notPaused {
    if (!POOL_MANAGER_FACTORY.isSupportedPool(_pool)) revert CorrectionsApplierJob_InvalidPool(_pool);
    PRICE_ORACLE.applyCorrection(_pool, _manipulatedIndex, _period);
    emit Worked(_pool, _manipulatedIndex, _period);
  }
}
