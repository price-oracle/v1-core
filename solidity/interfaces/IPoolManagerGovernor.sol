// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.4 <0.9.0;

import '@interfaces/IFeeManager.sol';
import '@interfaces/IPoolManagerDeployer.sol';
import '@interfaces/periphery/IPriceOracle.sol';
import '@interfaces/periphery/IGovernorMiniBravo.sol';
import '@interfaces/IPoolManagerFactory.sol';

/**
  @title PoolManager governance contract
  @notice This contract contains the data and logic necessary for the pool manager governance
 */
interface IPoolManagerGovernor is IGovernorMiniBravo {
  /*///////////////////////////////////////////////////////////////
                            ENUMS
  //////////////////////////////////////////////////////////////*/
  /**
    @notice The methods that are available for governance
   */
  enum Methods {
    Migrate,
    FeeManagerChange,
    PriceOracleChange
  }

  /*///////////////////////////////////////////////////////////////
                            ERRORS
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Thrown when the fee manager does not match the pool manager factory fee manager
    @param  _expected The expected fee manager
    @param  _actual The actual fee manager
   */
  error PoolManager_FeeManagerMismatch(IFeeManager _expected, IFeeManager _actual);

  /**
    @notice Thrown when trying to set an already set fee manager
   */
  error PoolManager_FeeManagerAlreadySet();

  /**
    @notice Thrown when the price oracle inputted does not match the poolManagerFactory priceOracle
    @param  _expected The expected price oracle
    @param  _actual The actual price oracle
   */
  error PoolManager_PriceOracleMismatch(IPriceOracle _expected, IPriceOracle _actual);

  /**
    @notice Thrown when trying to set an already set price oracle
   */
  error PoolManager_PriceOracleAlreadySet();

  /**
    @notice Thrown when the migration contract inputted does not match the poolManagerFactory migration contract
    @param  _expected The expected migration contract
    @param  _actual The actual migration contract
   */
  error PoolManager_MigrationContractMismatch(address _expected, address _actual);

  /**
    @notice Thrown when trying to migrate to a new PoolManager unsuccessful
   */
  error PoolManager_MigrationFailed();

  /*///////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Emitted when an old fee manager migrates to a new fee manager
    @param  _newFeeManager The new fee manager
   */
  event FeeManagerMigrated(IFeeManager _newFeeManager);

  /**
    @notice Emitted when the price oracle is set
    @param  _newPriceOracle The new price oracle
   */
  event PriceOracleSet(IPriceOracle _newPriceOracle);

  /*///////////////////////////////////////////////////////////////
                            VARIABLES
  //////////////////////////////////////////////////////////////*/

  /**
    @notice  Returns the pool manager factory contract
    @return  _poolManagerFactory The pool manager factory
   */
  function POOL_MANAGER_FACTORY() external view returns (IPoolManagerFactory _poolManagerFactory);

  /**
    @notice Returns the fee manager
    @return _feeManager The fee manager
   */
  function feeManager() external view returns (IFeeManager _feeManager);

  /**
    @notice Returns the pool liquidity
    @return _poolLiquidity The pool liquidity
   */
  function poolLiquidity() external view returns (uint256 _poolLiquidity);

  /**
    @notice Returns the liquidity seeded by the given donor
    @param  _donor The donor's address
    @return _seederBalance The amount of liquidity seeded by the donor
   */
  function seederBalance(address _donor) external view returns (uint256 _seederBalance);

  /**
    @notice Returns the liquidity seeded by the given donor that they burned
    @param  _donor The donor's address
    @return _seederBurned The amount of liquidity seeded by the donor that they burned
   */
  function seederBurned(address _donor) external view returns (uint256 _seederBurned);

  /**
    @notice Returns the price oracle
    @return _priceOracle The price oracle
   */
  function priceOracle() external view returns (IPriceOracle _priceOracle);

  /*///////////////////////////////////////////////////////////////
                            LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Creates a proposal to change the fee manager
    @dev    _newFeeManager must be equal to the current fee manager on the pool manager factory and
              different from the current fee manager
    @param  _newFeeManager The new fee manager to be set up
   */
  function proposeFeeManagerChange(IFeeManager _newFeeManager) external;

  /**
    @notice Votes yes on the proposal to change the fee manager
    @param  _newFeeManager The new fee manager to be set up
   */
  function acceptFeeManagerChange(IFeeManager _newFeeManager) external;

  /**
    @notice Creates a proposal to migrate
    @dev    _migrationContract must be equal to the current migration contract on
              the pool manager factory and different from the current migration contract
    @param  _migrationContract The migration contract
   */
  function proposeMigrate(address _migrationContract) external;

  /**
    @notice Votes yes on the proposal to migrate
    @param  _migrationContract The migration contract
   */
  function acceptMigrate(address _migrationContract) external;

  /**
    @notice Creates a proposal to change the price's oracle
    @dev    _newPriceOracle must be equal to the current price oracle on the
              pool manager factory and different from the current price's oracle
    @param  _newPriceOracle The new price oracle to be set up
   */
  function proposePriceOracleChange(IPriceOracle _newPriceOracle) external;

  /**
    @notice Votes yes on the proposal to change the prices oracle
    @param  _newPriceOracle The new price oracle to be set up
   */
  function acceptPriceOracleChange(IPriceOracle _newPriceOracle) external;
}
