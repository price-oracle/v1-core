// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.4 <0.9.0;

import 'isolmate/tokens/ERC20.sol';
import 'isolmate/interfaces/tokens/IERC20.sol';
import 'isolmate/utils/SafeTransferLib.sol';
import '@openzeppelin/contracts/utils/Strings.sol';
import '@interfaces/ILockManager.sol';
import '@interfaces/jobs/IFeeCollectorJob.sol';

import '@contracts/LockManagerGovernor.sol';
import '@contracts/utils/GasCheckLib.sol';
import '@contracts/utils/PRBMath.sol';

contract LockManager is ERC20, ILockManager, LockManagerGovernor {
  using SafeTransferLib for IERC20;

  /// @inheritdoc ILockManager
  IUniswapV3Pool public immutable POOL;

  /// @inheritdoc ILockManager
  IPoolManager public immutable POOL_MANAGER;

  /// @inheritdoc ILockManager
  IERC20 public immutable WETH;

  /// @inheritdoc ILockManager
  IERC20 public immutable TOKEN;

  /// @inheritdoc ILockManager
  IStrategy public immutable STRATEGY;

  /// @inheritdoc ILockManager
  uint24 public immutable FEE;

  /// @inheritdoc ILockManager
  bool public immutable IS_WETH_TOKEN0;

  /// @inheritdoc ILockManager
  mapping(address => UserRewards) public userRewards;

  /// @inheritdoc ILockManager
  PoolRewards public poolRewards;

  /// @inheritdoc ILockManager
  WithdrawalData public withdrawalData;

  /// @inheritdoc ILockManager
  uint256 public concentratedWeth;

  /**
    @notice Internal array with all liquidity positions
   */
  IStrategy.LiquidityPosition[] internal _positionsList;

  /**
    @notice lowerTick => upperTick => liquidity positions owned by this contract
   */
  mapping(int24 => mapping(int24 => uint128)) internal _positionsLiquidity;

  /**
    @notice The pool tick spacing
   */
  int24 internal immutable _TICK_SPACING;

  /**
    @notice Base to avoid over/underflow
   */
  uint256 internal constant _BASE = 1 ether;

  /**
    @notice The percentage of the fees to be distributed to maintain the pool
   */
  uint256 internal constant _TAX_PERCENTAGE = 20_000;

  /**
    @notice The fixed point precision of the distribution ratios
   */
  uint256 internal constant _DISTRIBUTION_BASE = 100_000;

  /**
    @dev payable constructor does not waste gas on checking msg.value
   */
  constructor(IPoolManager _poolManager, IPoolManager.LockManagerParams memory _lockManagerParams)
    payable
    ERC20('LockedWETH', '', 18)
    LockManagerGovernor(_lockManagerParams)
  {
    STRATEGY = _lockManagerParams.strategy;
    FEE = _lockManagerParams.fee;
    TOKEN = _lockManagerParams.token;
    POOL_MANAGER = _poolManager;
    POOL = _lockManagerParams.pool;
    IS_WETH_TOKEN0 = _lockManagerParams.isWethToken0;
    _TICK_SPACING = POOL.tickSpacing();
    WETH = _lockManagerParams.weth;

    // ERC20
    symbol = _getSymbol(_lockManagerParams.token, _lockManagerParams.index);
  }

  // ********* DEPRECATION ********* //

  /// @inheritdoc ILockManager
  function withdraw(address _receiver) external {
    WithdrawalData memory _withdrawalData = withdrawalData;
    if (!_withdrawalData.withdrawalsEnabled) revert LockManager_WithdrawalsNotEnabled();
    address _user = msg.sender;
    uint256 _userBalance = balanceOf[_user];
    if (_userBalance == 0) revert LockManager_ZeroBalance();

    uint256 _totalLocked = totalSupply;
    uint256 _totalWeth = _withdrawalData.totalWeth;
    uint256 _totalToken = _withdrawalData.totalToken;

    _burn(_userBalance);

    uint256 _wethAmount = (_userBalance * _totalWeth) / _totalLocked;
    uint256 _tokenAmount = (_userBalance * _totalToken) / _totalLocked;

    _withdrawalData.totalWeth = _withdrawalData.totalWeth - _wethAmount;
    _withdrawalData.totalToken = _withdrawalData.totalToken - _tokenAmount;
    withdrawalData = _withdrawalData;

    (uint256 _rewardWeth, uint256 _rewardToken) = _claimable(_user);

    _wethAmount = _wethAmount + _rewardWeth;
    _tokenAmount = _tokenAmount + _rewardToken;

    (uint256 _wethPerLockedWeth, uint256 _tokenPerLockedWeth) = _rewardRates();

    userRewards[_user] = UserRewards({wethAvailable: 0, tokenAvailable: 0, wethPaid: _wethPerLockedWeth, tokenPaid: _tokenPerLockedWeth});

    if (_wethAmount > 0) {
      WETH.safeTransfer(_receiver, _wethAmount);
    }

    if (_tokenAmount > 0) {
      TOKEN.safeTransfer(_receiver, _tokenAmount);
    }
  }

  /// @inheritdoc ILockManager
  function unwind(uint256 _positionsCount) external {
    if (!deprecated) revert LockManager_DeprecationRequired();
    uint256 _positionsLength = _positionsList.length;
    if (_positionsLength == 0) revert LockManager_NoPositions();
    if (_positionsLength < _positionsCount) revert LockManager_NoPositions();

    IPriceOracle _priceOracle = POOL_MANAGER_FACTORY.priceOracle();
    if (_priceOracle.isManipulated(POOL)) revert LockManager_PoolManipulated();

    uint256 _totalToken0;
    uint256 _totalToken1;

    // Loops the array from last to first
    IStrategy.LiquidityPosition memory _position;
    uint256 _lastIndexToCheck = _positionsLength - _positionsCount;
    while (_positionsLength > _lastIndexToCheck) {
      uint256 _index = _positionsLength - 1;
      _position = _positionsList[_index];
      int24 _lowerTick = _position.lowerTick;
      int24 _upperTick = _position.upperTick;
      uint128 _currentLiquidity = _positionsLiquidity[_lowerTick][_upperTick];
      // If liquidity is 0, then the position has already been burned
      if (_currentLiquidity > 0) {
        // Burns the position and account for WETH/Token
        (uint256 _amount0Burn, uint256 _amount1Burn) = _burnPosition(_lowerTick, _upperTick, _currentLiquidity);
        // Collects owed fees from burning the position and send to fee manager
        (uint128 _amount0Collect, uint128 _amount1Collect) = POOL.collect(
          address(this),
          _lowerTick,
          _upperTick,
          type(uint128).max,
          type(uint128).max
        );

        _totalToken0 += _amount0Collect - _amount0Burn;
        _totalToken1 += _amount1Collect - _amount1Burn;
      }

      // Deletes the position from the list
      _positionsList.pop();

      // Checks for zero index. If zero, mark it as withdrawable. We don't have any more active positions!
      if (_index == 0) {
        withdrawalData.withdrawalsEnabled = true;
        emit WithdrawalsEnabled();
      }

      unchecked {
        --_positionsLength;
      }
    }

    _feesDistribution(_totalToken0, _totalToken1);
  }

  // ********* ERC20 ********* //

  function _getSymbol(IERC20 _token, uint256 _index) internal view returns (string memory _symbol) {
    _symbol = string(abi.encodePacked('LockedWETHv1-', _token.symbol(), '-', Strings.toString(FEE), '-', Strings.toString(_index)));
  }

  /**
    @notice Transfers the locked WETH to another address
    @dev    The rewards are updated to make the virtual reward concrete so that they can claim at any point in the future
    @dev    This way, both sender and receiver won't be able to claim twice or manipulate the rewards
    @param  _to The address of the recipient
    @param  _amount The amount of locked WETH to be sent
    @return _success Whether the transfer succeeded or not
   */
  function transfer(address _to, uint256 _amount) public override(ERC20, IERC20) returns (bool _success) {
    if (msg.sender == _to) revert LockManager_InvalidAddress();
    _transferVotes(msg.sender, _to, _amount);
    _updateReward(msg.sender);
    _updateReward(_to);
    _success = super.transfer(_to, _amount);
    if (!_success) revert LockManager_TransferFailed();
  }

  /**
    @notice Transfers _amount of locked WETH between _from and _to
    @dev    The rewards are updated to make the virtual reward concrete so that they can claim at any point in the future
    @dev    This way, both sender and receiver won't be able to claim twice or manipulate the rewards
    @param  _from The sender of the funds
    @param  _to The address receiving the funds
    @param  _amount The amount of locked WETH to send
    @return _success Whether the transfer succeeded or not
   */
  function transferFrom(
    address _from,
    address _to,
    uint256 _amount
  ) public override(ERC20, IERC20) returns (bool _success) {
    if (_from == _to) revert LockManager_InvalidAddress();
    _transferVotes(_from, _to, _amount);
    _updateReward(_from);
    _updateReward(_to);
    _success = super.transferFrom(_from, _to, _amount);
    if (!_success) revert LockManager_TransferFailed();
  }

  // ********* REWARDS ********* //
  /// @inheritdoc ILockManager
  function claimable(address _account) external view returns (uint256 _wethClaimable, uint256 _tokenClaimable) {
    (_wethClaimable, _tokenClaimable) = _claimable(_account);
  }

  /// @inheritdoc ILockManager
  function lock(uint256 _wethAmount) public notDeprecated {
    if (_wethAmount == 0) revert LockManager_ZeroAmount();

    withdrawalData.totalWeth = withdrawalData.totalWeth + _wethAmount;

    _updateReward(msg.sender);
    _mint(msg.sender, _wethAmount);
    WETH.safeTransferFrom(msg.sender, address(this), _wethAmount);

    emit Locked(_wethAmount);
  }

  /// @inheritdoc ILockManager
  function burn(uint256 _lockedWethAmount) external notDeprecated {
    _burn(_lockedWethAmount);
  }

  /**
    @notice Burns the amount of lockedWeth provided by the caller
    @param  _lockedWethAmount The amount of lockedWeth to be burned
   */
  function _burn(uint256 _lockedWethAmount) internal {
    _cancelVotes(msg.sender, _lockedWethAmount);

    _updateReward(msg.sender);

    _burn(msg.sender, _lockedWethAmount);

    emit Burned(_lockedWethAmount);
  }

  /// @inheritdoc ILockManager
  function claimRewards(address _to) external returns (uint256 _rewardWeth, uint256 _rewardToken) {
    if (_to == address(0)) revert LockManager_ZeroAddress();

    address _account = msg.sender;
    (_rewardWeth, _rewardToken) = _claimable(_account);

    if (_rewardWeth == 0 && _rewardToken == 0) revert LockManager_NoRewardsToClaim();

    (uint256 _wethPerLockedWeth, uint256 _tokenPerLockedWeth) = _rewardRates();

    userRewards[_account] = UserRewards({wethAvailable: 0, tokenAvailable: 0, wethPaid: _wethPerLockedWeth, tokenPaid: _tokenPerLockedWeth});

    if (_rewardWeth > 0) {
      WETH.safeTransfer(_to, _rewardWeth);
    }

    if (_rewardToken > 0) {
      TOKEN.safeTransfer(_to, _rewardToken);
    }
    emit ClaimedRewards(msg.sender, _to, _rewardWeth, _rewardToken);
  }

  /// @inheritdoc ILockManager
  function addRewards(uint256 _wethAmount, uint256 _tokenAmount) public notDeprecated {
    _addRewards(_wethAmount, _tokenAmount);

    WETH.safeTransferFrom(msg.sender, address(this), _wethAmount);
    TOKEN.safeTransferFrom(msg.sender, address(this), _tokenAmount);
  }

  /**
    @notice Accounts for rewards to lockers
    @param  _wethAmount The amount of WETH added as rewards
    @param  _tokenAmount The amount of non-WETH added as rewards
   */
  function _addRewards(uint256 _wethAmount, uint256 _tokenAmount) internal {
    if (_wethAmount == 0 && _tokenAmount == 0) revert LockManager_ZeroAmount();
    uint256 _totalLocked = totalSupply;
    if (_totalLocked == 0) revert LockManager_NoLockedWeth();

    (uint256 _wethPerLockedWeth, uint256 _tokenPerLockedWeth) = _rewardRates();

    poolRewards = PoolRewards({
      wethPerLockedWeth: _wethPerLockedWeth + PRBMath.mulDiv(_wethAmount, _BASE, _totalLocked),
      tokenPerLockedWeth: _tokenPerLockedWeth + PRBMath.mulDiv(_tokenAmount, _BASE, _totalLocked)
    });

    emit RewardsAdded(_wethAmount, _tokenAmount);
  }

  /**
    @notice Calculates the amount of rewards generated by the pool manager per locked WETH and non-WETH token
    @return _wethPerLockedWeth The amount of rewards in WETH
    @return _tokenPerLockedWeth The amount of rewards in the non-WETH token
   */
  function _rewardRates() internal view returns (uint256 _wethPerLockedWeth, uint256 _tokenPerLockedWeth) {
    PoolRewards memory _poolRewards = poolRewards;
    (_wethPerLockedWeth, _tokenPerLockedWeth) = (_poolRewards.wethPerLockedWeth, _poolRewards.tokenPerLockedWeth);
  }

  /**
    @notice Updates the pool manager rewards for a given user
    @param  _account The address of the user
   */
  function _updateReward(address _account) internal {
    (uint256 _wethPerLockedWeth, uint256 _tokenPerLockedWeth) = _rewardRates();
    uint256 _userBalance = balanceOf[_account];

    UserRewards memory _userRewards = userRewards[_account];

    _userRewards.wethAvailable += PRBMath.mulDiv(_userBalance, _wethPerLockedWeth - _userRewards.wethPaid, _BASE);
    _userRewards.tokenAvailable += PRBMath.mulDiv(_userBalance, _tokenPerLockedWeth - _userRewards.tokenPaid, _BASE);
    _userRewards.wethPaid = _wethPerLockedWeth;
    _userRewards.tokenPaid = _tokenPerLockedWeth;

    userRewards[_account] = _userRewards;
  }

  /**
    @notice Returns the amounts of WETH and non-WETH token rewards that user can claim from a pool manager
    @param  _account The address of the user
    @return _wethClaimable The amount of WETH rewards claimable by the user
    @return _tokenClaimable The amount of non-WETH token rewards claimable by the user
   */
  function _claimable(address _account) internal view returns (uint256 _wethClaimable, uint256 _tokenClaimable) {
    (uint256 _wethPerLockedWeth, uint256 _tokenPerLockedWeth) = _rewardRates();
    uint256 _userBalance = balanceOf[_account];

    UserRewards memory _userRewards = userRewards[_account];

    uint256 _claimWethShare = PRBMath.mulDiv(_userBalance, _wethPerLockedWeth - _userRewards.wethPaid, _BASE);
    uint256 _claimTokenShare = PRBMath.mulDiv(_userBalance, _tokenPerLockedWeth - _userRewards.tokenPaid, _BASE);

    _wethClaimable = _claimWethShare + _userRewards.wethAvailable;
    _tokenClaimable = _claimTokenShare + _userRewards.tokenAvailable;
  }

  // ********* CONCENTRATED POSITIONS ********* //

  /// @inheritdoc ILockManager
  function getPositionsCount() external view returns (uint256 _positionsCount) {
    _positionsCount = _positionsList.length;
  }

  /// @inheritdoc ILockManager
  function positionsList(uint256 _startFrom, uint256 _amount) external view returns (IStrategy.LiquidityPosition[] memory _positions) {
    uint256 _length = _positionsList.length;

    if (_amount > _length - _startFrom) {
      _amount = _length - _startFrom;
    }

    _positions = new IStrategy.LiquidityPosition[](_amount);

    uint256 _index;
    while (_index < _amount) {
      _positions[_index] = _positionsList[_startFrom + _index];

      unchecked {
        ++_index;
      }
    }
  }

  /// @inheritdoc ILockManager
  function mintPosition() external notDeprecated {
    IPriceOracle _priceOracle = POOL_MANAGER_FACTORY.priceOracle();
    if (_priceOracle.isManipulated(POOL)) revert LockManager_PoolManipulated();

    IStrategy.LiquidityPosition memory _positionToMint = _getPositionToMint();

    uint128 _currentLiquidity = _positionsLiquidity[_positionToMint.lowerTick][_positionToMint.upperTick];

    // New position
    if (_currentLiquidity == 0) {
      _positionsList.push(_positionToMint);
    }
    // Updates Position Liquidity
    _positionsLiquidity[_positionToMint.lowerTick][_positionToMint.upperTick] = _currentLiquidity + _positionToMint.liquidity;

    (uint256 _amount0, uint256 _amount1) = POOL.mint(
      address(this),
      _positionToMint.lowerTick, // int24
      _positionToMint.upperTick, // int24
      _positionToMint.liquidity, // uint128
      abi.encode() // bytes calldata
    );

    // We're not updating token amount because the lock manager only mints 100% WETH positions
    if (IS_WETH_TOKEN0) {
      withdrawalData.totalWeth = withdrawalData.totalWeth - _amount0;
    } else {
      withdrawalData.totalWeth = withdrawalData.totalWeth - _amount1;
    }

    emit PositionMinted(_positionToMint, _amount0, _amount1);
  }

  /// @inheritdoc ILockManager
  function burnPosition(IStrategy.Position calldata _position) external notDeprecated {
    IPriceOracle _priceOracle = POOL_MANAGER_FACTORY.priceOracle();
    if (_priceOracle.isManipulated(POOL)) revert LockManager_PoolManipulated();

    IStrategy.LiquidityPosition memory _positionToBurn = _getPositionToBurn(_position);

    (uint256 _amount0Burn, uint256 _amount1Burn) = _burnPosition(
      _positionToBurn.lowerTick,
      _positionToBurn.upperTick,
      _positionsLiquidity[_positionToBurn.lowerTick][_positionToBurn.upperTick]
    );
    // Collects owed from burning the position and send to fee manager
    (uint128 _totalCollect0, uint128 _totalCollect1) = POOL.collect(
      address(this),
      _positionToBurn.lowerTick,
      _positionToBurn.upperTick,
      type(uint128).max,
      type(uint128).max
    );

    uint256 _feesAmount0 = _totalCollect0 - _amount0Burn;
    uint256 _feesAmount1 = _totalCollect1 - _amount1Burn;

    _feesDistribution(_feesAmount0, _feesAmount1);

    emit PositionBurned(_positionToBurn, _amount0Burn, _amount1Burn);
  }

  /// @inheritdoc ILockManager
  function getPositionToMint() external view returns (IStrategy.LiquidityPosition memory _positionToMint) {
    _positionToMint = _getPositionToMint();
  }

  /**
    @notice Get the the position to mint from the strategy
    @return _positionToMint The position that has to be minted
   */
  function _getPositionToMint() internal view returns (IStrategy.LiquidityPosition memory _positionToMint) {
    IStrategy.LockManagerState memory _lockManagerState = IStrategy.LockManagerState({
      poolManager: POOL_MANAGER,
      pool: POOL,
      availableWeth: withdrawalData.totalWeth,
      isWethToken0: IS_WETH_TOKEN0,
      tickSpacing: _TICK_SPACING
    });

    _positionToMint = STRATEGY.getPositionToMint(_lockManagerState);
  }

  /// @inheritdoc ILockManager
  function getPositionToBurn(IStrategy.Position calldata _position) external view returns (IStrategy.LiquidityPosition memory _positionToBurn) {
    _positionToBurn = _getPositionToBurn(_position);
  }

  /**
    @notice Get the position to burn from strategy
    @param  _position The position to burn
    @return _positionToBurn The position that has to be burned
   */
  function _getPositionToBurn(IStrategy.Position calldata _position) internal view returns (IStrategy.LiquidityPosition memory _positionToBurn) {
    IStrategy.LockManagerState memory _lockManagerState = IStrategy.LockManagerState({
      poolManager: POOL_MANAGER,
      pool: POOL,
      availableWeth: withdrawalData.totalWeth,
      isWethToken0: IS_WETH_TOKEN0,
      tickSpacing: _TICK_SPACING
    });

    _positionToBurn = STRATEGY.getPositionToBurn(_position, _positionsLiquidity[_position.lowerTick][_position.upperTick], _lockManagerState);
  }

  // ********** UniswapV3 ***********

  /// @inheritdoc ILockManager
  function uniswapV3MintCallback(
    uint256 _amount0Owed,
    uint256 _amount1Owed,
    bytes calldata /* _data */
  ) external notDeprecated {
    if (msg.sender != address(POOL)) revert LockManager_OnlyPool();

    uint256 _owedWeth = IS_WETH_TOKEN0 ? _amount0Owed : _amount1Owed;
    concentratedWeth += _owedWeth;

    if (concentratedWeth > totalSupply) revert LockManager_OverLimitMint(totalSupply, concentratedWeth);

    WETH.safeTransfer(address(POOL), _owedWeth);
  }

  // ********** FEES ***********

  /// @inheritdoc ILockManager
  function collectFees(IStrategy.Position[] calldata _positions) external {
    IUniswapV3Pool _pool = POOL;
    IPoolManagerFactory _poolManagerFactory = POOL_MANAGER_FACTORY;
    IFeeCollectorJob _feeCollectorJob = _poolManagerFactory.feeCollectorJob();
    uint256 _positionsCount = _positions.length;
    uint256 _positionIndex;
    uint256 _amount0;
    uint256 _amount1;
    uint256 _totalToken0;
    uint256 _totalToken1;
    IStrategy.Position memory _position;

    if (address(_feeCollectorJob) == msg.sender) {
      if (_poolManagerFactory.priceOracle().isManipulated(_pool)) revert LockManager_PoolManipulated();
      uint256 _collectMultiplier = _feeCollectorJob.collectMultiplier();
      uint256 _slot0CostPerPosition = GasCheckLib.SLOT0_GAS_USAGE / _positionsCount;
      (uint160 _sqrtPriceX96, , , , , , ) = _pool.slot0();

      while (_positionIndex < _positionsCount) {
        _position = _positions[_positionIndex];
        (_amount0, _amount1) = GasCheckLib.collectFromConcentratedPosition(
          _pool,
          _sqrtPriceX96,
          _collectMultiplier,
          _slot0CostPerPosition,
          _position.lowerTick,
          _position.upperTick,
          IS_WETH_TOKEN0
        );

        _totalToken0 += _amount0;
        _totalToken1 += _amount1;
        unchecked {
          ++_positionIndex;
        }
      }
    } else {
      while (_positionIndex < _positionsCount) {
        _position = _positions[_positionIndex];
        _pool.burn(_position.lowerTick, _position.upperTick, 0);
        (_amount0, _amount1) = _pool.collect(address(this), _position.lowerTick, _position.upperTick, type(uint128).max, type(uint128).max);

        _totalToken0 += _amount0;
        _totalToken1 += _amount1;
        unchecked {
          ++_positionIndex;
        }
      }
    }

    _feesDistribution(_totalToken0, _totalToken1);
  }

  /**
    @notice Calculates the amount of non-WETH tokens and WETH to be allocated to the fee manager
    @param  _totalToken0 The amount of token0 fees
    @param  _totalToken1 The amount of token1 fees
   */
  function _feesDistribution(uint256 _totalToken0, uint256 _totalToken1) internal {
    if (_totalToken0 == 0 && _totalToken1 == 0) return;
    IFeeManager _feeManager = POOL_MANAGER.feeManager();

    (uint256 _totalWeth, uint256 _totalToken) = IS_WETH_TOKEN0 ? (_totalToken0, _totalToken1) : (_totalToken1, _totalToken0);
    uint256 _taxWeth = PRBMath.mulDiv(_totalWeth, _TAX_PERCENTAGE, _DISTRIBUTION_BASE);
    uint256 _taxToken = PRBMath.mulDiv(_totalToken, _TAX_PERCENTAGE, _DISTRIBUTION_BASE);

    _addRewards(_totalWeth - _taxWeth, _totalToken - _taxToken);

    /*
      Transfer the taxes to the fee manager. Important to transfer first and then call `depositFromLockManager`
      Otherwise, there won't be enough balance in FeeManager to pay for maintenance and cardinality
     */
    WETH.safeTransfer(address(_feeManager), _taxWeth);
    IERC20(TOKEN).safeTransfer(address(_feeManager), _taxToken);
    _feeManager.depositFromLockManager(_taxWeth, _taxToken);

    emit FeesCollected(_totalWeth, _totalToken);
  }

  /**
    @notice Burns a position from an amount of liquidity
    @param  _lowerTick The lower tick of the position
    @param  _upperTick The upper tick of the position
    @param  _currentLiquidity The amount of liquidity to burn
    @return _amount0Burn The amount of token0 released from the position
    @return _amount1Burn The amount of token1 released from the position
   */
  function _burnPosition(
    int24 _lowerTick,
    int24 _upperTick,
    uint128 _currentLiquidity
  ) internal returns (uint256 _amount0Burn, uint256 _amount1Burn) {
    _positionsLiquidity[_lowerTick][_upperTick] = 0;

    (_amount0Burn, _amount1Burn) = POOL.burn(
      _lowerTick, // int24
      _upperTick, // int24
      _currentLiquidity // uint128
    );

    if (IS_WETH_TOKEN0) {
      withdrawalData.totalWeth = withdrawalData.totalWeth + _amount0Burn;
      withdrawalData.totalToken = withdrawalData.totalToken + _amount1Burn;
    } else {
      withdrawalData.totalToken = withdrawalData.totalToken + _amount0Burn;
      withdrawalData.totalWeth = withdrawalData.totalWeth + _amount1Burn;
    }
  }

  /// @inheritdoc IGovernorMiniBravo
  function votingPower(address _user) public view override(GovernorMiniBravo, IGovernorMiniBravo) returns (uint256 _balance) {
    _balance = balanceOf[_user];
  }

  /// @inheritdoc IGovernorMiniBravo
  function totalVotes() public view override(GovernorMiniBravo, IGovernorMiniBravo) returns (uint256 _totalVotes) {
    _totalVotes = totalSupply;
  }
}
