// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.4 <0.9.0;

import '@interfaces/IPoolManagerGovernor.sol';
import '@interfaces/IPoolManagerDeployer.sol';
import '@contracts/periphery/GovernorMiniBravo.sol';

abstract contract PoolManagerGovernor is IPoolManagerGovernor, GovernorMiniBravo {
  /// @inheritdoc IPoolManagerGovernor
  IPoolManagerFactory public immutable POOL_MANAGER_FACTORY;
  /// @inheritdoc IPoolManagerGovernor
  IFeeManager public feeManager;
  /// @inheritdoc IPoolManagerGovernor
  IPriceOracle public priceOracle;
  /// @inheritdoc IPoolManagerGovernor
  uint256 public poolLiquidity;
  /// @inheritdoc IPoolManagerGovernor
  mapping(address => uint256) public seederBalance;
  /// @inheritdoc IPoolManagerGovernor
  mapping(address => uint256) public seederBurned;

  bytes internal constant _MIGRATE = abi.encodeWithSignature('migrate()');

  constructor() payable GovernorMiniBravo() {
    POOL_MANAGER_FACTORY = IPoolManagerDeployer(msg.sender).POOL_MANAGER_FACTORY();
    address _admin;
    (, , , , feeManager, priceOracle, _admin, , ) = POOL_MANAGER_FACTORY.constructorArguments();
    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
  }

  /**
    @notice Executes a proposal
    @param  _method The method to be called
    @param  _parameters The parameters to be sent to that method
   */
  function _execute(uint256 _method, bytes memory _parameters) internal override {
    Methods _poolManagerMethod = Methods(_method);
    if (_poolManagerMethod == Methods.Migrate) {
      address _migrationContract = abi.decode(_parameters, (address));
      (bool _success, ) = _migrationContract.delegatecall(_MIGRATE);
      if (!_success) revert PoolManager_MigrationFailed();
    } else if (_poolManagerMethod == Methods.FeeManagerChange) {
      IFeeManager _newFeeManager = abi.decode(_parameters, (IFeeManager));
      _setFeeManager(_newFeeManager);
    } else if (_poolManagerMethod == Methods.PriceOracleChange) {
      IPriceOracle _newPriceOracle = abi.decode(_parameters, (IPriceOracle));
      _setPriceOracle(_newPriceOracle);
    }
  }

  /**
    @notice Returns true if the contract address can be changed to the new one for a particular method
    @dev    _newContract must be different from the current address for the proposal
    @param  _newContract The new contract to be set up
    @param  _method The method to be called
    @return _canChange True if the contract can be changed to _newContract
   */
  function _changeAvailable(address _newContract, uint256 _method) internal view returns (bool _canChange) {
    if (_proposals[_method].length == 0) {
      return true;
    }

    Proposal memory _currentProposal = _getLatest(_method);
    if (keccak256(_currentProposal.params) != keccak256(abi.encode(_newContract))) {
      _canChange = true;
    }
  }

  /**
    @notice Sets a new fee manager
    @param  _newFeeManager The new fee manager to be set up
   */
  function _setFeeManager(IFeeManager _newFeeManager) internal {
    feeManager.migrateTo(_newFeeManager);
    feeManager = _newFeeManager;
    emit FeeManagerMigrated(_newFeeManager);
  }

  /**
    @notice Sets a new price oracle
    @param  _newPriceOracle The new price oracle to be set up
   */
  function _setPriceOracle(IPriceOracle _newPriceOracle) internal {
    priceOracle = _newPriceOracle;
    emit PriceOracleSet(_newPriceOracle);
  }

  /// @inheritdoc IPoolManagerGovernor
  function proposeFeeManagerChange(IFeeManager _newFeeManager) external {
    if (_newFeeManager != POOL_MANAGER_FACTORY.feeManager())
      revert PoolManager_FeeManagerMismatch(POOL_MANAGER_FACTORY.feeManager(), _newFeeManager);
    if (_newFeeManager == feeManager) revert PoolManager_FeeManagerAlreadySet();
    if (_changeAvailable(address(_newFeeManager), uint256(Methods.FeeManagerChange))) {
      _propose(uint256(Methods.FeeManagerChange), abi.encode(_newFeeManager));
    }
  }

  /// @inheritdoc IPoolManagerGovernor
  function acceptFeeManagerChange(IFeeManager _newFeeManager) external {
    _acceptProposal(uint256(Methods.FeeManagerChange), abi.encode(_newFeeManager), msg.sender);
  }

  /// @inheritdoc IPoolManagerGovernor
  function proposePriceOracleChange(IPriceOracle _newPriceOracle) external {
    if (_newPriceOracle != POOL_MANAGER_FACTORY.priceOracle())
      revert PoolManager_PriceOracleMismatch(POOL_MANAGER_FACTORY.priceOracle(), _newPriceOracle);
    if (_newPriceOracle == priceOracle) revert PoolManager_PriceOracleAlreadySet();
    if (_changeAvailable(address(_newPriceOracle), uint256(Methods.PriceOracleChange))) {
      _propose(uint256(Methods.PriceOracleChange), abi.encode(_newPriceOracle));
    }
  }

  /// @inheritdoc IPoolManagerGovernor
  function acceptPriceOracleChange(IPriceOracle _newPriceOracle) external {
    _acceptProposal(uint256(Methods.PriceOracleChange), abi.encode(_newPriceOracle), msg.sender);
  }

  /// @inheritdoc IPoolManagerGovernor
  function proposeMigrate(address _migrationContract) external {
    if (_migrationContract != POOL_MANAGER_FACTORY.poolManagerMigrator())
      revert PoolManager_MigrationContractMismatch(POOL_MANAGER_FACTORY.poolManagerMigrator(), _migrationContract);

    if (_changeAvailable(_migrationContract, uint256(Methods.Migrate))) {
      _propose(uint256(Methods.Migrate), abi.encode(_migrationContract));
    }
  }

  /// @inheritdoc IPoolManagerGovernor
  function acceptMigrate(address _migrationContract) external {
    _acceptProposal(uint256(Methods.Migrate), abi.encode(_migrationContract), msg.sender);
  }

  /// @inheritdoc IGovernorMiniBravo
  function votingPower(address _user) public view virtual override(GovernorMiniBravo, IGovernorMiniBravo) returns (uint256 _balance) {
    _balance = seederBalance[_user] + seederBurned[_user];
  }

  /// @inheritdoc IGovernorMiniBravo
  function totalVotes() public view virtual override(GovernorMiniBravo, IGovernorMiniBravo) returns (uint256 _totalVotes) {
    _totalVotes = poolLiquidity;
  }
}
