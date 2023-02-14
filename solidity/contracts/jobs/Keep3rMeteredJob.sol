// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.4 <0.9.0;

import 'keep3r/interfaces/IKeep3rHelper.sol';

import '@interfaces/jobs/IKeep3rMeteredJob.sol';
import '@contracts/jobs/Keep3rJob.sol';

abstract contract Keep3rMeteredJob is IKeep3rMeteredJob, Keep3rJob {
  /// @inheritdoc IKeep3rMeteredJob
  IKeep3rHelper public keep3rHelper = IKeep3rHelper(0xeDDe080E28Eb53532bD1804de51BD9Cd5cADF0d4);
  /// @inheritdoc IKeep3rMeteredJob
  uint256 public gasMultiplier = 10_000;
  /// @notice Used to calculate rewards with precision
  uint32 internal constant _BASE = 10_000;

  modifier upkeepMetered(address _keeper) {
    uint256 _initialGas = gasleft();
    _isValidKeeper(_keeper);
    _;
    uint256 _gasAfterWork = gasleft();
    uint256 _reward = keep3rHelper.getRewardAmountFor(_keeper, _initialGas - _gasAfterWork);
    _reward = (_reward * gasMultiplier) / _BASE;
    keep3r.bondedPayment(_keeper, _reward);
    emit GasMetered(_initialGas, _gasAfterWork);
  }

  /// @inheritdoc IKeep3rMeteredJob
  function setKeep3rHelper(IKeep3rHelper _keep3rHelper) public onlyGovernor {
    keep3rHelper = _keep3rHelper;
    emit Keep3rHelperChanged(_keep3rHelper);
  }

  /// @inheritdoc IKeep3rMeteredJob
  function setGasMultiplier(uint256 _gasMultiplier) external onlyGovernor {
    gasMultiplier = _gasMultiplier;
    emit GasMultiplierChanged(gasMultiplier);
  }
}
