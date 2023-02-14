// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.4 <0.9.0;

import 'keep3r/interfaces/IKeep3rHelper.sol';
import '@interfaces/jobs/IKeep3rJob.sol';

interface IKeep3rMeteredJob is IKeep3rJob {
  /*///////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/
  /// @notice Emitted when a new Keep3rHelper contract is set
  /// @param _keep3rHelper Address of the new Keep3rHelper contract
  event Keep3rHelperChanged(IKeep3rHelper _keep3rHelper);

  /// @notice Emitted when a new gas bonus multiplier is set
  /// @param _gasMultiplier Multiplier that boosts gas record to calculate the keeper reward
  event GasMultiplierChanged(uint256 _gasMultiplier);

  /// @notice Emitted when a metered job is worked
  /// @param _initialGas First gas record registered
  /// @param _gasAfterWork Gas record registered after work
  event GasMetered(uint256 _initialGas, uint256 _gasAfterWork);

  /*///////////////////////////////////////////////////////////////
                              VARIABLES
  //////////////////////////////////////////////////////////////*/
  /// @notice Returns the address of the Keep3r helper contract
  /// @return _keep3rHelper Address of the Keep3r helper contract
  function keep3rHelper() external view returns (IKeep3rHelper _keep3rHelper);

  /// @notice Returns the multiplier that boosts gas record to calculate the keeper reward
  /// @return _gasMultiplier Multiplier that boosts gas record to calculate the keeper reward
  function gasMultiplier() external view returns (uint256 _gasMultiplier);

  /*///////////////////////////////////////////////////////////////
                              LOGIC
  //////////////////////////////////////////////////////////////*/
  /// @notice Allows governor to set a new Keep3r helper contract
  /// @param _keep3rHelper Address of the new Keep3r helper contract
  function setKeep3rHelper(IKeep3rHelper _keep3rHelper) external;

  /// @notice Allows governor to set a new gas multiplier
  /// @param _gasMultiplier New multiplier that boosts gas record to calculate the keeper reward
  function setGasMultiplier(uint256 _gasMultiplier) external;
}
