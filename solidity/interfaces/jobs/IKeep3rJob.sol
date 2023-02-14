// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.4 <0.9.0;

import 'isolmate/interfaces/tokens/IERC20.sol';
import 'uni-v3-core/interfaces/IUniswapV3Pool.sol';
import 'keep3r/interfaces/IKeep3r.sol';
import 'solidity-utils/interfaces/IPausable.sol';

interface IKeep3rJob is IPausable {
  /*///////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Emitted a new keeper is set
    @param  _keep3r The new keeper address
   */
  event Keep3rSet(IKeep3r _keep3r);

  /**
    @notice Emitted when setting new keeper requirements
    @param  _bond The required token to bond by keepers
    @param  _minBond The minimum amount bound
    @param  _earnings The earnings of the keeper
    @param  _age The age of the keeper in the Keep3r network
   */
  event Keep3rRequirementsSet(IERC20 _bond, uint256 _minBond, uint256 _earnings, uint256 _age);

  /*///////////////////////////////////////////////////////////////
                              ERRORS
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Thrown when the caller is not a valid keeper in the Keep3r network
   */
  error InvalidKeeper();

  /*///////////////////////////////////////////////////////////////
                            VARIABLES
  //////////////////////////////////////////////////////////////*/

  /**
    @notice The address of the Keep3r contract
    @return _keep3r The address of the token
   */
  function keep3r() external view returns (IKeep3r _keep3r);

  /**
    @notice The address of the keeper bond token
    @return _requiredBond The address of the token
   */
  function requiredBond() external view returns (IERC20 _requiredBond);

  /**
    @notice The minimum amount of bonded token required to bond by the keeper
    @return _requiredMinBond The required min amount bond
   */
  function requiredMinBond() external view returns (uint256 _requiredMinBond);

  /**
    @notice The required earnings of the keeper
    @return _requiredEarnings The required earnings
   */
  function requiredEarnings() external view returns (uint256 _requiredEarnings);

  /**
    @notice The age of the keeper in the Keep3r network
    @return _requiredAge The age of the keeper, in seconds
   */
  function requiredAge() external view returns (uint256 _requiredAge);

  /*///////////////////////////////////////////////////////////////
                              LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Sets the address of the keeper
    @param  _keep3r The address of the keeper to be set
   */
  function setKeep3r(IKeep3r _keep3r) external;

  /**
    @notice Sets the keeper requirements
    @param  _bond The required token to bond by keepers
    @param  _minBond The minimum amount bound
    @param  _earnings The earnings of the keeper
    @param  _age The age of the keeper in the Keep3r network
   */
  function setKeep3rRequirements(
    IERC20 _bond,
    uint256 _minBond,
    uint256 _earnings,
    uint256 _age
  ) external;
}
