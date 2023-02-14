// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.4 <0.9.0;

import 'isolmate/interfaces/tokens/IERC20.sol';
import 'uni-v3-core/interfaces/IUniswapV3Pool.sol';

import '@interfaces/IPoolManager.sol';
import '@interfaces/ILockManagerFactory.sol';
import '@interfaces/IPoolManagerDeployer.sol';
import '@interfaces/IFeeManager.sol';
import '@interfaces/periphery/IPriceOracle.sol';
import '@interfaces/strategies/IStrategy.sol';
import '@interfaces/jobs/IFeeCollectorJob.sol';

/**
  @notice Creates a new pool manager associated with a defined UniswapV3 pool
  @dev    The UniswapV3 pool needs to be a pool deployed by the current UniswapV3 factory.
            The pool might or might not already exist (the correct deterministic address is checked
            but not called).
 */
interface IPoolManagerFactory {
  /**
    @notice Used to pass constructor arguments when deploying new pool (will call msg.sender.constructorArguments()),
              to avoid having to retrieve them when checking if the sender is a valid pool manager address
   */
  struct PoolManagerParams {
    IUniswapV3Factory uniswapV3Factory;
    bytes32 poolBytecodeHash;
    IERC20 weth;
    IERC20 otherToken;
    IFeeManager feeManager;
    IPriceOracle priceOracle;
    address owner;
    uint24 fee;
    uint160 sqrtPriceX96;
  }

  /*///////////////////////////////////////////////////////////////
                              ERRORS
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Thrown when changing the default fee to a nonexistent pool
   */
  error PoolManagerFactory_InvalidPool();

  /**
    @notice Thrown when trying to create a pool manager that was already created
   */
  error PoolManagerFactory_ExistingPoolManager();

  /**
    @notice Thrown when zero address was supplied to a function
   */
  error PoolManagerFactory_ZeroAddress();

  /**
    @notice Thrown when an invalid account tries to accept ownership of the contract
   */
  error PoolManagerFactory_InvalidPendingOwner();

  /**
    @notice Thrown when creating a PoolManager with less than the min ETH amount
   */
  error PoolManagerFactory_SmallAmount();

  /**
    @notice Thrown when trying to set min ETH amount to 0
   */
  error PoolManagerFactory_InvalidMinEthAmount();

  /*///////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Emitted when the lock manager factory changes
    @param  _lockManagerFactory The new lock manager Factory
   */
  event LockManagerFactoryChanged(ILockManagerFactory _lockManagerFactory);

  /**
    @notice Emitted when the strategy changes
    @param  _strategy The new strategy
   */
  event StrategyChanged(IStrategy _strategy);

  /**
    @notice Emitted when a new owner is nominated
    @param  _owner The nominated owner
   */
  event OwnerNominated(address _owner);

  /**
    @notice Emitted when the owner changes
    @param  _owner The new owner
   */
  event OwnerChanged(address _owner);

  /**
    @notice Emitted when the migrator address changes
    @param  _poolManagerMigrator The new migrator address
   */
  event PoolManagerMigratorChanged(address _poolManagerMigrator);

  /**
    @notice Emitted when the fee manager address changes
    @param  _feeManager The new fee manager address
   */
  event FeeManagerChanged(IFeeManager _feeManager);

  /**
    @notice Emitted when the price oracle address changes
    @param  _priceOracle The new price oracle address
   */
  event PriceOracleChanged(IPriceOracle _priceOracle);

  /**
    @notice Emitted when the fee collector job changes
    @param  _feeCollectorJob The new fee collector job
   */
  event FeeCollectorJobChanged(IFeeCollectorJob _feeCollectorJob);

  /**
    @notice Emitted when the pool manager is created
    @param  _poolManager The new pool manager
   */
  event PoolManagerCreated(IPoolManager _poolManager);

  /**
    @notice Emitted when the min ETH amount changes
    @param  _minEthAmount The new min ETH amount
   */
  event MinEthAmountChanged(uint256 _minEthAmount);

  /*///////////////////////////////////////////////////////////////
                            VARIABLES
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Returns the UniswapV3 factory contract
    @return _uniswapV3Factory The UniswapV3 factory contract
   */
  function UNISWAP_V3_FACTORY() external view returns (IUniswapV3Factory _uniswapV3Factory);

  /**
    @notice Returns the UniswapV3 pool bytecode hash
    @return _poolBytecodeHash The UniswapV3 pool bytecode hash
   */
  function POOL_BYTECODE_HASH() external view returns (bytes32 _poolBytecodeHash);

  /**
    @notice The role that allows changing the Strategy
   */
  function STRATEGY_SETTER_ROLE() external view returns (bytes32);

  /**
    @notice The role that allows changing the lock manager factory
   */
  function FACTORY_SETTER_ROLE() external view returns (bytes32);

  /**
    @notice The role that allows changing the pool manager migrator address
   */
  function MIGRATOR_SETTER_ROLE() external view returns (bytes32);

  /**
    @notice The role that allows changing the price oracle address
   */
  function PRICE_ORACLE_SETTER_ROLE() external view returns (bytes32);

  /**
    @notice The role that allows changing the fee manager address
   */
  function FEE_MANAGER_SETTER_ROLE() external view returns (bytes32);

  /**
    @notice The role that allows changing the fee collector job
   */
  function FEE_COLLECTOR_SETTER_ROLE() external view returns (bytes32);

  /**
    @notice The role that allows changing the min ETH amount to create a PoolManager
   */
  function MIN_ETH_AMOUNT_SETTER_ROLE() external view returns (bytes32);

  /**
    @notice Returns the WETH token contract
    @return _weth The WETH token contract
   */
  function WETH() external view returns (IERC20 _weth);

  /**
    @notice Returns the strategy registry
    @return _strategy The strategy registry
   */
  function strategy() external view returns (IStrategy _strategy);

  /**
    @notice Returns the fee manager
    @return _feeManager The fee manager
   */
  function feeManager() external view returns (IFeeManager _feeManager);

  /**
    @notice Returns the total number of pool managers that this factory has deployed
    @return _childrenCount The total amount of pool managers created by this factory
   */
  function childrenCount() external view returns (uint256 _childrenCount);

  /**
    @notice Returns the fee collector job
    @return _feeCollectorJob The fee collector job
   */
  function feeCollectorJob() external view returns (IFeeCollectorJob _feeCollectorJob);

  /**
    @notice Returns the lock manager factory
    @return _lockManagerFactory The lock manager factory
   */
  function lockManagerFactory() external view returns (ILockManagerFactory _lockManagerFactory);

  /**
    @notice Returns the pool manager deployer
    @return _poolManagerDeployer The pool manager deployer
   */
  function POOL_MANAGER_DEPLOYER() external view returns (IPoolManagerDeployer _poolManagerDeployer);

  /**
    @notice Returns the pool manager migrator contract
    @return _poolManagerMigrator The pool manager migrator contract
   */
  function poolManagerMigrator() external view returns (address _poolManagerMigrator);

  /**
    @notice Returns the price oracle
    @return _priceOracle The price oracle
   */
  function priceOracle() external view returns (IPriceOracle _priceOracle);

  /**
    @notice Returns the minimum amount of ETH to create a PoolManager
    @return _minEthAmount The minimum amount of ETH
   */
  function minEthAmount() external view returns (uint256 _minEthAmount);

  /**
    @notice Getter for a pool manager params public variable used to initialize a new pool manager factory
    @dev    This method is called by the pool manager constructor (no parameters are passed not to influence the
              deterministic address)
    @return uniswapV3Factory Address of the UniswapV3 factory
    @return poolBytecodeHash Bytecode hash of the UniswapV3 pool
    @return weth The WETH token
    @return otherToken The non-WETH token in the UniswapV3 pool address
    @return feeManager The fee manager contract
    @return priceOracle The price oracle contract
    @return owner The contracts owner
    @return fee The UniswapV3 fee tier, as a 10000th of %
    @return sqrtPriceX96 A sqrt price representing the current pool prices
   */
  // solhint-disable wonderland/non-state-vars-leading-underscore
  function constructorArguments()
    external
    view
    returns (
      IUniswapV3Factory uniswapV3Factory,
      bytes32 poolBytecodeHash,
      IERC20 weth,
      IERC20 otherToken,
      IFeeManager feeManager,
      IPriceOracle priceOracle,
      address owner,
      uint24 fee,
      uint160 sqrtPriceX96
    );

  /**
    @notice  Returns true if this factory deployed the given pool manager
    @param   _poolManager The pool manager to be checked
    @return  _isChild Whether the given pool manager was deployed by this factory
   */
  // solhint-enable wonderland/non-state-vars-leading-underscore
  function isChild(IPoolManager _poolManager) external view returns (bool _isChild);

  /**
    @notice Returns the address of the pool manager for a given pool, the zero address if there is no pool manager
    @param  _pool The address of the Uniswap V3 pool
    @return _poolManager The address of the pool manager for a given pool
   */
  function poolManagers(IUniswapV3Pool _pool) external view returns (IPoolManager _poolManager);

  /**
    @notice Returns the list of all the pool managers deployed by this factory
    @param  _index The index of the pool manager
    @return _poolManager The pool manager
   */
  function children(uint256 _index) external view returns (IPoolManager _poolManager);

  /**
    @notice Returns true if the pool has a valid pool manager
    @param  _pool The address of the Uniswap V3 pool
    @return _isSupportedPool True if the pool has a pool manager
   */
  function isSupportedPool(IUniswapV3Pool _pool) external view returns (bool _isSupportedPool);

  /**
    @notice Returns true if the token has a pool paired with WETH
    @param  _token The non-WETH token paired with WETH
    @return _isValid True if the token has a pool paired with WETH
   */
  function isSupportedToken(IERC20 _token) external view returns (bool _isValid);

  /**
    @notice Returns if a specific pair supports routing through WETH
    @param  _tokenA The tokenA to check paired with tokenB
    @param  _tokenB The tokenB to check paired with tokenA
    @return _isSupported True if the pair is supported
   */
  function isSupportedTokenPair(IERC20 _tokenA, IERC20 _tokenB) external view returns (bool _isSupported);

  /**
    @notice Returns the default fee to be used for a specific non-WETH token paired with WETH
    @param  _token The non-WETH token paired with WETH
    @return _fee The default fee for the non-WETH token on the WETH/TOKEN pool
   */
  function defaultTokenFee(IERC20 _token) external view returns (uint24 _fee);

  /**
    @notice Returns the fee tiers for a specific non-WETH token paired with WETH
    @param  _token The token paired with WETH
    @return _fees The fee tiers the non-WETH token on the WETH/TOKEN pool
   */
  function tokenFees(IERC20 _token) external view returns (uint24[] memory _fees);

  /**
    @notice Returns owner of the contract
    @return _owner The owner of the contract
   */
  function owner() external view returns (address _owner);

  /**
    @notice Returns the pending owner
    @return _pendingOwner The pending owner of the contract
   */
  function pendingOwner() external view returns (address _pendingOwner);

  /**
    @notice Returns the pool manager bytecode hash for deterministic addresses
    @return _poolManagerBytecodeHash The pool manager bytecode hash
   */
  function POOL_MANAGER_BYTECODE_HASH() external view returns (bytes32 _poolManagerBytecodeHash);

  /*///////////////////////////////////////////////////////////////
                              LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Deploys a new pool manager for a given UniswapV3 pool if it does not exist yet
    @param  _token The non-WETH token paired with WETH in the given pool
    @param  _fee The UniswapV3 pool fee tier, as a 10000th of %
    @param  _liquidity The liquidity to create the pool manager
    @param  _sqrtPriceX96 The sqrt price in base 96
    @return _poolManager The pool manager newly deployed
   */
  function createPoolManager(
    IERC20 _token,
    uint24 _fee,
    uint128 _liquidity,
    uint160 _sqrtPriceX96
  ) external returns (IPoolManager _poolManager);

  /**
    @notice Returns pagination of the pool managers deployed by this factory
    @param  _startFrom Index from where to start the pagination
    @param  _amount Maximum amount of pool managers to retrieve
    @return _list Paginated pool managers deployed by this factory
   */
  function listChildren(uint256 _startFrom, uint256 _amount) external view returns (IPoolManager[] memory _list);

  /**
    @notice Computes the deterministic address of a given pool manager, a non-WETH token, and the fee
    @param  _token The non-WETH token paired with WETH in the pool
    @param  _fee The UniswapV3 fee tier
    @return _theoreticalPoolManagerAddress The theoretical address of the pool manager
   */
  function getPoolManagerAddress(IERC20 _token, uint24 _fee) external view returns (IPoolManager _theoreticalPoolManagerAddress);

  /**
    @notice Computes the deterministic address of a UniswapV3 pool with WETH, given the non-WETH token and its fee tier.
    @param  _token The non-WETH token paired with WETH in the pool
    @param  _fee The UniswapV3 fee tier
    @return _theoreticalAddress Address of the theoretical address of the UniswapV3 pool
    @return _isWethToken0 Defines if WETH is the token0 of the UniswapV3 pool
   */
  function getWethPoolAddress(IERC20 _token, uint24 _fee) external view returns (IUniswapV3Pool _theoreticalAddress, bool _isWethToken0);

  /**
    @notice Lists the existing pool managers for a given token
    @param  _token The address of the token
    @param  _feeTiers The fee tiers to check
    @return _poolManagerAddresses The available pool managers
   */
  function getPoolManagers(IERC20 _token, uint24[] memory _feeTiers) external view returns (address[] memory _poolManagerAddresses);

  /**
    @notice Sets the default fee for the pool of non-WETH/WETH
    @param  _token The non-WETH token paired with WETH in the pool
    @param  _fee The UniswapV3 fee tier to use
   */
  function setDefaultTokenFee(IERC20 _token, uint24 _fee) external;

  /**
    @notice Sets the new strategy address
    @param  _strategy The new strategy address
   */
  function setStrategy(IStrategy _strategy) external;

  /**
    @notice Sets the new lock manager factory address
    @param  _lockManagerFactory The new lock manager factory address
   */
  function setLockManagerFactory(ILockManagerFactory _lockManagerFactory) external;

  /**
    @notice Nominates the new owner of the contract
    @param  _newOwner The new owner
   */
  function nominateOwner(address _newOwner) external;

  /**
    @notice Sets a new owner and grants all roles needed to manage the contract
   */
  function acceptOwnership() external;

  /**
    @notice Sets the contract address responsible for migrating
    @param  _poolManagerMigrator The new pool manager migrator
   */
  function setPoolManagerMigrator(address _poolManagerMigrator) external;

  /**
    @notice Sets price oracle contract
    @param  _priceOracle The new price oracle
   */
  function setPriceOracle(IPriceOracle _priceOracle) external;

  /**
    @notice Sets the fee manager contract
    @param  _feeManager The new fee manager
   */
  function setFeeManager(IFeeManager _feeManager) external;

  /**
    @notice Sets the fee collector job
    @param  _feeCollectorJob The new fee collector job
   */
  function setFeeCollectorJob(IFeeCollectorJob _feeCollectorJob) external;

  /**
    @notice Sets the minimum ETH amount
    @param  _minEthAmount The new minimum ETH amount
   */
  function setMinEthAmount(uint256 _minEthAmount) external;
}
