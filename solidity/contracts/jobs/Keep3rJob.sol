// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.4 <0.9.0;

import 'solidity-utils/contracts/Pausable.sol';
import 'solidity-utils/contracts/Governable.sol';

import '@interfaces/jobs/IKeep3rJob.sol';

abstract contract Keep3rJob is IKeep3rJob, Pausable {
  /// @inheritdoc IKeep3rJob
  IKeep3r public keep3r = IKeep3r(0xeb02addCfD8B773A5FFA6B9d1FE99c566f8c44CC);

  /// @inheritdoc IKeep3rJob
  IERC20 public requiredBond;

  /// @inheritdoc IKeep3rJob
  uint256 public requiredMinBond;

  /// @inheritdoc IKeep3rJob
  uint256 public requiredEarnings;

  /// @inheritdoc IKeep3rJob
  uint256 public requiredAge;

  /// @inheritdoc IKeep3rJob
  function setKeep3r(IKeep3r _keep3r) public onlyGovernor {
    keep3r = _keep3r;
    emit Keep3rSet(_keep3r);
  }

  /// @inheritdoc IKeep3rJob
  function setKeep3rRequirements(
    IERC20 _bond,
    uint256 _minBond,
    uint256 _earnings,
    uint256 _age
  ) public onlyGovernor {
    requiredBond = _bond;
    requiredMinBond = _minBond;
    requiredEarnings = _earnings;
    requiredAge = _age;
    emit Keep3rRequirementsSet(_bond, _minBond, _earnings, _age);
  }

  /**
    @notice Checks if the sender is a valid keeper in the Keep3r network
    @param  _keeper the address to check the keeper status
   */
  modifier upkeep(address _keeper) virtual {
    if (!_isValidKeeper(_keeper)) revert InvalidKeeper();
    _;
    keep3r.worked(_keeper);
  }

  /**
    @notice Checks if a keeper meets the bonding requirements
    @param  _keeper the address to check the keeper data
    @return _isValid true if the keeper meets the bonding requirements
   */
  function _isValidKeeper(address _keeper) internal virtual returns (bool _isValid) {
    return keep3r.isBondedKeeper(_keeper, address(requiredBond), requiredMinBond, requiredEarnings, requiredAge);
  }
}
