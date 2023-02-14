// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.4 <0.9.0;

import 'solidity-utils/contracts/Roles.sol';

import '@interfaces/IPoolManagerFactory.sol';

import '@contracts/PoolManager.sol';
import '@contracts/utils/PriceLib.sol';
import '@contracts/utils/LiquidityAmounts08.sol';

contract PoolManagerFactory is IPoolManagerFactory, Roles {
  /// @inheritdoc IPoolManagerFactory
  bytes32 public constant STRATEGY_SETTER_ROLE = keccak256('STRATEGY_SETTER');

  /// @inheritdoc IPoolManagerFactory
  bytes32 public constant FACTORY_SETTER_ROLE = keccak256('FACTORY_SETTER');

  /// @inheritdoc IPoolManagerFactory
  bytes32 public constant MIGRATOR_SETTER_ROLE = keccak256('MIGRATOR_SETTER');

  /// @inheritdoc IPoolManagerFactory
  bytes32 public constant FEE_MANAGER_SETTER_ROLE = keccak256('FEE_MANAGER_SETTER');

  /// @inheritdoc IPoolManagerFactory
  bytes32 public constant PRICE_ORACLE_SETTER_ROLE = keccak256('PRICE_ORACLE_SETTER');

  /// @inheritdoc IPoolManagerFactory
  bytes32 public constant FEE_COLLECTOR_SETTER_ROLE = keccak256('FEE_COLLECTOR_SETTER_ROLE');

  /// @inheritdoc IPoolManagerFactory
  bytes32 public constant MIN_ETH_AMOUNT_SETTER_ROLE = keccak256('MIN_ETH_AMOUNT_SETTER_ROLE');

  /// @inheritdoc IPoolManagerFactory
  mapping(IUniswapV3Pool => IPoolManager) public poolManagers;

  /// @inheritdoc IPoolManagerFactory
  mapping(IPoolManager => bool) public isChild;

  /// @inheritdoc IPoolManagerFactory
  mapping(uint256 => IPoolManager) public children;

  /// @inheritdoc IPoolManagerFactory
  IFeeManager public feeManager;

  /// @inheritdoc IPoolManagerFactory
  IPriceOracle public priceOracle;

  /// @inheritdoc IPoolManagerFactory
  IStrategy public strategy;

  /// @inheritdoc IPoolManagerFactory
  ILockManagerFactory public lockManagerFactory;

  /// @inheritdoc IPoolManagerFactory
  IFeeCollectorJob public feeCollectorJob;

  /// @inheritdoc IPoolManagerFactory
  PoolManagerParams public constructorArguments;

  /// @inheritdoc IPoolManagerFactory
  address public owner;

  /// @inheritdoc IPoolManagerFactory
  address public pendingOwner;

  /// @inheritdoc IPoolManagerFactory
  address public poolManagerMigrator;

  /// @inheritdoc IPoolManagerFactory
  uint256 public childrenCount;

  /// @inheritdoc IPoolManagerFactory
  uint256 public minEthAmount = 25 ether;

  /// @inheritdoc IPoolManagerFactory
  IUniswapV3Factory public immutable UNISWAP_V3_FACTORY;

  /// @inheritdoc IPoolManagerFactory
  bytes32 public immutable POOL_BYTECODE_HASH;

  /// @inheritdoc IPoolManagerFactory
  IERC20 public immutable WETH;

  /// @inheritdoc IPoolManagerFactory
  IPoolManagerDeployer public immutable POOL_MANAGER_DEPLOYER;

  /// @inheritdoc IPoolManagerFactory
  bytes32 public immutable POOL_MANAGER_BYTECODE_HASH;

  /**
    @notice The fee tiers for a particular token paired with WETH
   */
  mapping(IERC20 => uint24[]) internal _tokenFees;

  /**
    @notice UniswapV3's maximum tick
    @dev    Due to tick spacing, pools with different fees may have differences between _MAX_TICK and tickUpper.
            Use tickUpper to find the max tick of the pool
   */
  int24 internal constant _MAX_TICK = 887272;

  /// @notice The rounding threshold for minimum liquidity
  uint256 internal constant ROUNDING_THRESHOLD = 100;

  /**
    @dev payable constructor does not waste gas on checking msg.value
   */
  constructor(
    IStrategy _strategy,
    IFeeManager _feeManager,
    ILockManagerFactory _lockManagerFactory,
    IPriceOracle _priceOracle,
    IPoolManagerDeployer _poolManagerDeployer,
    IUniswapV3Factory _uniswapV3Factory,
    bytes32 _poolBytecodeHash,
    IERC20 _weth,
    address _owner
  ) payable {
    feeManager = _feeManager;
    strategy = _strategy;
    lockManagerFactory = _lockManagerFactory;
    owner = _owner;
    priceOracle = _priceOracle;
    POOL_MANAGER_DEPLOYER = _poolManagerDeployer;
    POOL_MANAGER_BYTECODE_HASH = keccak256(abi.encodePacked(type(PoolManager).creationCode));
    UNISWAP_V3_FACTORY = _uniswapV3Factory;
    POOL_BYTECODE_HASH = _poolBytecodeHash;
    WETH = _weth;
    _grantOwnerRoles(_owner);
  }

  /// @inheritdoc IPoolManagerFactory
  function createPoolManager(
    IERC20 _token,
    uint24 _fee,
    uint128 _liquidity,
    uint160 _sqrtPriceX96
  ) public returns (IPoolManager _poolManager) {
    (IUniswapV3Pool _pool, ) = PriceLib._calculateTheoreticalAddress(WETH, _token, _fee, UNISWAP_V3_FACTORY, POOL_BYTECODE_HASH);
    IPoolManager _expectedPoolManager = PriceLib._getPoolManager(POOL_MANAGER_DEPLOYER, POOL_MANAGER_BYTECODE_HASH, _pool);

    // Reverts in case the pool manager was already created by this factory
    if (isChild[_expectedPoolManager]) revert PoolManagerFactory_ExistingPoolManager();

    uint256 _totalInWETH = _getTotalInWETHForLiquidity(_sqrtPriceX96, _fee, _liquidity, _token);
    // Take into account rounding issues and apply the rounding threshold
    if (_totalInWETH + ROUNDING_THRESHOLD < minEthAmount) revert PoolManagerFactory_SmallAmount();

    // Saves the pool manager as a child of this factory
    poolManagers[_pool] = _expectedPoolManager;
    children[childrenCount] = _expectedPoolManager;
    isChild[_expectedPoolManager] = true;
    ++childrenCount;
    _tokenFees[_token].push(_fee);

    // Deploys and initializes the pool manager
    constructorArguments = PoolManagerParams({
      uniswapV3Factory: UNISWAP_V3_FACTORY,
      poolBytecodeHash: POOL_BYTECODE_HASH,
      weth: WETH,
      otherToken: _token,
      feeManager: feeManager,
      priceOracle: priceOracle,
      owner: owner,
      fee: _fee,
      sqrtPriceX96: _sqrtPriceX96
    });

    _poolManager = _createPoolManager(_pool);
    _poolManager.increaseFullRangePosition(msg.sender, _liquidity, _sqrtPriceX96);

    delete constructorArguments;

    emit PoolManagerCreated(_poolManager);
  }

  /// @inheritdoc IPoolManagerFactory
  function isSupportedPool(IUniswapV3Pool _pool) external view returns (bool _isSupportedPool) {
    _isSupportedPool = address(poolManagers[_pool]) != address(0);
  }

  /// @inheritdoc IPoolManagerFactory
  function isSupportedToken(IERC20 _token) external view returns (bool _isSupportedToken) {
    _isSupportedToken = _tokenFees[_token].length != 0;
  }

  /// @inheritdoc IPoolManagerFactory
  function isSupportedTokenPair(IERC20 _tokenA, IERC20 _tokenB) external view returns (bool _isSupportedTokenPair) {
    _isSupportedTokenPair = _tokenFees[_tokenA].length != 0 && _tokenFees[_tokenB].length != 0;
  }

  /// @inheritdoc IPoolManagerFactory
  function tokenFees(IERC20 _token) external view returns (uint24[] memory _fees) {
    _fees = _tokenFees[_token];
  }

  /// @inheritdoc IPoolManagerFactory
  function defaultTokenFee(IERC20 _token) external view returns (uint24 _fee) {
    _fee = _tokenFees[_token][0];
  }

  /// @inheritdoc IPoolManagerFactory
  /**
      @dev  When _tokenFees length == 1, the for loop will throw out of bounds,
            this is ok since the default is already set,
            and there are no other values to change the default to
   */
  // TODO: Enable changing the default fee permissionlessly https://linear.app/defi-wonderland/issue/PRI-210
  function setDefaultTokenFee(IERC20 _token, uint24 _fee) external onlyRole(DEFAULT_ADMIN_ROLE) {
    uint256 _tokenFeesLengthMinus1 = _tokenFees[_token].length - 1;
    uint256 _i = 1;
    while (_i < _tokenFeesLengthMinus1) {
      if (_tokenFees[_token][_i] == _fee) break;

      unchecked {
        ++_i;
      }
    }
    // If it's the last index, we check if it effectively found it.
    if (_i == _tokenFeesLengthMinus1 && _tokenFees[_token][_i] != _fee) revert PoolManagerFactory_InvalidPool();
    _tokenFees[_token][_i] = _tokenFees[_token][0];
    _tokenFees[_token][0] = _fee;
  }

  /// @inheritdoc IPoolManagerFactory
  function listChildren(uint256 _startFrom, uint256 _amount) external view returns (IPoolManager[] memory _list) {
    uint256 _length = childrenCount;
    if (_amount > _length - _startFrom) {
      _amount = _length - _startFrom;
    }

    _list = new IPoolManager[](_amount);

    uint256 _index;
    while (_index < _amount) {
      _list[_index] = children[_startFrom + _index];

      unchecked {
        ++_index;
      }
    }

    return _list;
  }

  /// @inheritdoc IPoolManagerFactory
  function getPoolManagerAddress(IERC20 _token, uint24 _fee) external view returns (IPoolManager _theoreticalPoolManagerAddress) {
    (IUniswapV3Pool _theoreticalPoolAddress, ) = PriceLib._calculateTheoreticalAddress(
      WETH,
      _token,
      _fee,
      UNISWAP_V3_FACTORY,
      POOL_BYTECODE_HASH
    );
    _theoreticalPoolManagerAddress = PriceLib._getPoolManager(POOL_MANAGER_DEPLOYER, POOL_MANAGER_BYTECODE_HASH, _theoreticalPoolAddress);
  }

  /// @inheritdoc IPoolManagerFactory
  function getWethPoolAddress(IERC20 _token, uint24 _fee) external view returns (IUniswapV3Pool _theoreticalAddress, bool _isWethToken0) {
    (_theoreticalAddress, _isWethToken0) = PriceLib._calculateTheoreticalAddress(WETH, _token, _fee, UNISWAP_V3_FACTORY, POOL_BYTECODE_HASH);
  }

  /// @inheritdoc IPoolManagerFactory
  function getPoolManagers(IERC20 _token, uint24[] calldata _feeTiers) external view returns (address[] memory _poolManagerAddresses) {
    uint256 _feeTiersCount = _feeTiers.length;
    _poolManagerAddresses = new address[](_feeTiersCount);
    uint256 _i;
    IPoolManagerDeployer _poolManagerDeployer = POOL_MANAGER_DEPLOYER;

    while (_i < _feeTiersCount) {
      (IUniswapV3Pool _theoreticalPoolAddress, ) = PriceLib._calculateTheoreticalAddress(
        WETH,
        _token,
        _feeTiers[_i],
        UNISWAP_V3_FACTORY,
        POOL_BYTECODE_HASH
      );
      IPoolManager _expectedPoolManager = PriceLib._getPoolManager(_poolManagerDeployer, POOL_MANAGER_BYTECODE_HASH, _theoreticalPoolAddress);

      if (isChild[_expectedPoolManager]) {
        _poolManagerAddresses[_i] = address(_expectedPoolManager);
      } else {
        _poolManagerAddresses[_i] = address(0);
      }
      unchecked {
        ++_i;
      }
    }
  }

  // ******* LOCK MANAGER *******
  /// @inheritdoc IPoolManagerFactory
  function setLockManagerFactory(ILockManagerFactory _lockManagerFactory) external onlyRole(FACTORY_SETTER_ROLE) {
    if (address(_lockManagerFactory) == address(0)) revert PoolManagerFactory_ZeroAddress();
    lockManagerFactory = _lockManagerFactory;
    emit LockManagerFactoryChanged(_lockManagerFactory);
  }

  // ******* STRATEGY *******
  /// @inheritdoc IPoolManagerFactory
  function setStrategy(IStrategy _strategy) external onlyRole(STRATEGY_SETTER_ROLE) {
    if (address(_strategy) == address(0)) revert PoolManagerFactory_ZeroAddress();
    strategy = _strategy;
    emit StrategyChanged(_strategy);
  }

  // ******* OWNERSHIP *******
  /// @inheritdoc IPoolManagerFactory
  function nominateOwner(address _newOwner) external onlyRole(DEFAULT_ADMIN_ROLE) {
    pendingOwner = _newOwner;
    emit OwnerNominated(_newOwner);
  }

  /// @inheritdoc IPoolManagerFactory
  function acceptOwnership() external {
    address _newOwner = pendingOwner;
    if (msg.sender != _newOwner) revert PoolManagerFactory_InvalidPendingOwner();

    address _owner = owner;
    _revokeRole(DEFAULT_ADMIN_ROLE, _owner);
    _revokeRole(FACTORY_SETTER_ROLE, _owner);
    _revokeRole(STRATEGY_SETTER_ROLE, _owner);
    _revokeRole(MIGRATOR_SETTER_ROLE, _owner);
    _revokeRole(FEE_MANAGER_SETTER_ROLE, _owner);
    _revokeRole(PRICE_ORACLE_SETTER_ROLE, _owner);
    _revokeRole(FEE_COLLECTOR_SETTER_ROLE, _owner);
    _revokeRole(MIN_ETH_AMOUNT_SETTER_ROLE, _owner);

    owner = _newOwner;
    pendingOwner = address(0);
    _grantOwnerRoles(_newOwner);

    emit OwnerChanged(_newOwner);
  }

  /// @inheritdoc IPoolManagerFactory
  function setPoolManagerMigrator(address _poolManagerMigrator) external onlyRole(MIGRATOR_SETTER_ROLE) {
    poolManagerMigrator = _poolManagerMigrator;
    emit PoolManagerMigratorChanged(_poolManagerMigrator);
  }

  /// @inheritdoc IPoolManagerFactory
  function setFeeManager(IFeeManager _feeManager) external onlyRole(FEE_MANAGER_SETTER_ROLE) {
    if (address(_feeManager) == address(0)) revert PoolManagerFactory_ZeroAddress();
    feeManager = _feeManager;
    emit FeeManagerChanged(_feeManager);
  }

  /// @inheritdoc IPoolManagerFactory
  function setPriceOracle(IPriceOracle _priceOracle) external onlyRole(PRICE_ORACLE_SETTER_ROLE) {
    if (address(_priceOracle) == address(0)) revert PoolManagerFactory_ZeroAddress();
    priceOracle = _priceOracle;
    emit PriceOracleChanged(_priceOracle);
  }

  /// @inheritdoc IPoolManagerFactory
  function setFeeCollectorJob(IFeeCollectorJob _feeCollectorJob) external onlyRole(FEE_COLLECTOR_SETTER_ROLE) {
    if (address(_feeCollectorJob) == address(0)) revert PoolManagerFactory_ZeroAddress();
    feeCollectorJob = _feeCollectorJob;
    emit FeeCollectorJobChanged(_feeCollectorJob);
  }

  /// @inheritdoc IPoolManagerFactory
  function setMinEthAmount(uint256 _minEthAmount) external onlyRole(MIN_ETH_AMOUNT_SETTER_ROLE) {
    if (_minEthAmount == 0) revert PoolManagerFactory_InvalidMinEthAmount();
    minEthAmount = _minEthAmount;
    emit MinEthAmountChanged(_minEthAmount);
  }

  /**
    @notice Grants _owner all permissions needed to manage this contract
    @param  _owner The address that will be granted with the permissions
   */
  function _grantOwnerRoles(address _owner) internal {
    _grantRole(DEFAULT_ADMIN_ROLE, _owner);
    _grantRole(FACTORY_SETTER_ROLE, _owner);
    _grantRole(STRATEGY_SETTER_ROLE, _owner);
    _grantRole(MIGRATOR_SETTER_ROLE, _owner);
    _grantRole(FEE_MANAGER_SETTER_ROLE, _owner);
    _grantRole(PRICE_ORACLE_SETTER_ROLE, _owner);
    _grantRole(FEE_COLLECTOR_SETTER_ROLE, _owner);
    _grantRole(MIN_ETH_AMOUNT_SETTER_ROLE, _owner);
  }

  /**
    @notice Creates a new pool manager
    @param  _pool The deployed UniswapV3 pool
    @return _poolManager The pool manager deployed
   */
  function _createPoolManager(IUniswapV3Pool _pool) internal returns (IPoolManager _poolManager) {
    _poolManager = POOL_MANAGER_DEPLOYER.deployPoolManager(_pool);
  }

  /**
    @notice Returns the total amount in WETH for a given amount of liquidity, the current
            pool price and the prices at the tick boundaries
    @param _sqrtPriceX96 A sqrt price representing the current pool prices
    @param _fee The UniswapV3 pool fee tier
    @param _liquidity The liquidity being valued
    @param _token The non-WETH token
    @return _totalInWeth The total amount of WETH
   */
  function _getTotalInWETHForLiquidity(
    uint160 _sqrtPriceX96,
    uint24 _fee,
    uint128 _liquidity,
    IERC20 _token
  ) internal view returns (uint256 _totalInWeth) {
    int24 _tickUpper = _MAX_TICK - (_MAX_TICK % UNISWAP_V3_FACTORY.feeAmountTickSpacing(_fee));
    int24 _tickLower = -_tickUpper;
    bool _isWethToken0 = address(WETH) < address(_token);

    if (_isWethToken0) {
      uint160 _maxSqrtRatioX96 = TickMath.getSqrtRatioAtTick(_tickUpper);
      // We need to use LiquidityAmounts08 as FullMath is not compatible with solidity 0.8 and should be able to under/overflow.
      // getAmount0ForLiquidity relies on going into overflow and then coming back to a normal range to work.
      _totalInWeth = LiquidityAmounts08.getAmount0ForLiquidity(_sqrtPriceX96, _maxSqrtRatioX96, _liquidity);
    } else {
      uint160 _minSqrtRatioX96 = TickMath.getSqrtRatioAtTick(_tickLower);
      _totalInWeth = LiquidityAmounts08.getAmount1ForLiquidity(_minSqrtRatioX96, _sqrtPriceX96, _liquidity);
    }
  }
}
