// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.4 <0.9.0;

import 'isolmate/interfaces/tokens/IERC20.sol';
import 'uni-v3-core/interfaces/IUniswapV3Pool.sol';

import '@interfaces/ILockManagerGovernor.sol';
import '@interfaces/periphery/IPriceOracle.sol';
import '@interfaces/strategies/IStrategy.sol';

/**
  @title LockManager contract
  @notice This contract allows users to lock WETH and claim fees from the concentrated positions.
 */
interface ILockManager is IERC20, ILockManagerGovernor {
  /*///////////////////////////////////////////////////////////////
                              ERRORS
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Thrown when the user doesn't have rewards to claim
   */
  error LockManager_NoRewardsToClaim();

  /**
    @notice Thrown when the amount is zero
   */
  error LockManager_ZeroAmount();

  /**
    @notice Thrown when the provided address is zero
   */
  error LockManager_ZeroAddress();

  /**
    @notice Thrown when the lock manager has no locked WETH
   */
  error LockManager_NoLockedWeth();

  /**
    @notice Thrown when the UniswapV3 callback caller is not a valid pool
   */
  error LockManager_OnlyPool();

  /**
    @notice Thrown when the amount of WETH minted by this lock manager exceeds the WETH supply
    @param  _totalSupply The locked WETH supply
    @param  _concentratedWeth The amount of WETH minted by this lock manager
   */
  error LockManager_OverLimitMint(uint256 _totalSupply, uint256 _concentratedWeth);

  /**
    @notice Thrown when enabling withdraws without the lockManager being deprecated
   */
  error LockManager_DeprecationRequired();

  /**
    @notice Thrown when trying to withdraw with the contract not marked as withdrawable
   */
  error LockManager_WithdrawalsNotEnabled();

  /**
    @notice Thrown when trying to withdraw with zero lockedWeth
   */
  error LockManager_ZeroBalance();

  /**
    @notice Thrown when the caller is not the lock manager
   */
  error LockManager_NotLockManager();

  /**
    @notice Thrown when trying to unwind, and there are no positions left
   */
  error LockManager_NoPositions();

  /**
      @notice Thrown when the price oracle detects a manipulation
   */
  error LockManager_PoolManipulated();

  /**
    @notice Thrown when trying to transfer to the same address
   */
  error LockManager_InvalidAddress();

  /**
    @notice Thrown when transfer or transferFrom fails
   */
  error LockManager_TransferFailed();

  /*///////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Emitted when a user locks WETH in a pool
    @param  _wethAmount The amount of WETH tokens to lock
   */
  event Locked(uint256 _wethAmount);

  /**
    @notice Emitted when a user claims rewards
    @param  _user The address of the user that claimed the rewards
    @param  _wethAmount The amount of WETH tokens to claim
    @param  _tokenAmount The amount of non-WETH tokens to claim
   */
  event ClaimedRewards(address _user, address _to, uint256 _wethAmount, uint256 _tokenAmount);

  /**
    @notice Emitted when a fee manager adds WETH rewards to a given pool manager
    @param  _wethAmount The amount of WETH added
    @param  _tokenAmount The amount of WETH added
   */
  event RewardsAdded(uint256 _wethAmount, uint256 _tokenAmount);

  /**
    @notice Emitted when we finish the fee-collecting process
    @param  _wethFees Total fees from concentrated positions in WETH
    @param  _tokenFees Total fees from concentrated positions in non-WETH token
   */
  event FeesCollected(uint256 _wethFees, uint256 _tokenFees);

  /**
    @notice Emitted when an amount of locked WETH is burned
    @param _wethAmount The amount of burned locked WETH
   */
  event Burned(uint256 _wethAmount);

  /**
    @notice Emitted when withdrawals are enabled
   */
  event WithdrawalsEnabled();

  /**
    @notice Emitted when a position was minted
    @param _position The position
    @param _amount0 The amount of token0 supplied for the position
    @param _amount1 The amount of token1 supplied for the position
   */
  event PositionMinted(IStrategy.LiquidityPosition _position, uint256 _amount0, uint256 _amount1);

  /**
    @notice Emitted when a position was burned
    @param _position The position
    @param _amount0 The amount of token0 released from the position
    @param _amount1 The amount of token1 released from the position
   */
  event PositionBurned(IStrategy.LiquidityPosition _position, uint256 _amount0, uint256 _amount1);

  /*///////////////////////////////////////////////////////////////
                              STRUCTS
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Pool status for internal accountancy
    @param  wethPerLockedWeth The value of the reward per WETH locked
    @param  tokenPerLockedWeth The value of the reward per Token locked
   */
  struct PoolRewards {
    uint256 wethPerLockedWeth;
    uint256 tokenPerLockedWeth;
  }

  /**
    @notice The amounts of paid and available rewards per user
    @param  wethPaid The WETH amount already claimed
    @param  tokenPaid The non-WETH token amount already claimed
    @param  wethAvailable The available WETH amount
    @param  tokenAvailable The available non-WETH token amount
   */
  struct UserRewards {
    uint256 wethPaid;
    uint256 tokenPaid;
    uint256 wethAvailable;
    uint256 tokenAvailable;
  }

  /**
    @notice Withdrawal data for balance withdrawals for lockers
    @param  withdrawalsEnabled True if all concentrated positions were burned and the balance can be withdrawn
    @param  totalWeth The total WETH to distribute between lockers
    @param  totalToken The total token to distribute between lockers
   */
  struct WithdrawalData {
    bool withdrawalsEnabled;
    uint256 totalWeth;
    uint256 totalToken;
  }

  /*///////////////////////////////////////////////////////////////
                            VARIABLES
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Returns the WETH contract
    @return _weth The WETH token
   */
  function WETH() external view returns (IERC20 _weth);

  /**
    @notice Returns the status of a corresponding pool manager
    @return wethPerLockedWeth The value of the reward per WETH locked
    @return tokenPerLockedWeth The value of the reward per Token locked
   */
  // solhint-disable wonderland/non-state-vars-leading-underscore
  function poolRewards() external view returns (uint256 wethPerLockedWeth, uint256 tokenPerLockedWeth);

  /**
    @notice Returns the underlying uni v3 pool contract
    @return _pool The underlying uni v3 pool contract
   */
  function POOL() external view returns (IUniswapV3Pool _pool);

  /**
    @notice Returns the pool manager contract
    @return _poolManager The pool manager
   */
  function POOL_MANAGER() external view returns (IPoolManager _poolManager);

  /**
    @notice Returns true if WETH token is the token0
    @return _isWethToken0 If WETH is token0
   */
  function IS_WETH_TOKEN0() external view returns (bool _isWethToken0);

  /**
    @notice  Returns the pending to the corresponding account
    @param   _account The address of the account
    @return  wethPaid The amount of the claimed rewards in WETH
    @return  tokenPaid The amount of the claimed rewards in non-WETH token
    @return  wethAvailable The amount of the pending rewards in WETH
    @return  tokenAvailable The amount of the pending rewards in non-WETH token
   */
  // solhint-disable wonderland/non-state-vars-leading-underscore
  function userRewards(address _account)
    external
    view
    returns (
      uint256 wethPaid,
      uint256 tokenPaid,
      uint256 wethAvailable,
      uint256 tokenAvailable
    );

  /**
    @notice Returns the withdrawal data
    @return withdrawalsEnabled True if lock manager is deprecated and all positions have been unwound
    @return totalWeth The total amount of WETH to distribute between lockers
    @return totalToken the total amount of non-WETH token to distribute between lockers
   */
  // solhint-disable wonderland/non-state-vars-leading-underscore
  function withdrawalData()
    external
    view
    returns (
      bool withdrawalsEnabled,
      uint256 totalWeth,
      uint256 totalToken
    );

  /**
    @notice Returns the strategy
    @return _strategy The strategy
   */
  function STRATEGY() external view returns (IStrategy _strategy);

  /**
    @notice Returns the fee of the pool manager
    @return _fee The fee
   */
  function FEE() external view returns (uint24 _fee);

  /**
    @notice Returns the non-WETH token contract of the underlying pool
    @return _token The non-WETH token contract of the underlying pool
   */
  function TOKEN() external view returns (IERC20 _token);

  /**
    @notice Returns the total amount of WETH minted by this lock manager
    @return _concentratedWeth The total amount of WETH in use by this lock manager
   */
  function concentratedWeth() external view returns (uint256 _concentratedWeth);

  /*///////////////////////////////////////////////////////////////
                              LOGIC
  //////////////////////////////////////////////////////////////*/

  // ********* REWARDS ********* //
  /**
    @notice  Get the total WETH claimable for a given account and pool manager
    @dev     This value is calculated by adding the balance and unclaimed rewards.
    @param   _account The address of the account
    @return  _wethClaimable The amount of WETH claimable
    @return  _tokenClaimable The amount of Token claimable
   */
  function claimable(address _account) external view returns (uint256 _wethClaimable, uint256 _tokenClaimable);

  /**
    @notice  Lock the amount of WETH token provided by the caller
    @dev     Same amount of WETH lock token will be provided
    @param   _wethAmount The amount of WETH tokens that the caller wants to provide
   */
  function lock(uint256 _wethAmount) external;

  /**
    @notice Returns the rewards generated by a caller in a specific pool manager
    @param  _to The recipient of these rewards
    @return _rewardWeth The amount of rewards in WETH that have been claimed
    @return _rewardToken The amount of rewards in non-WETH tokens that have been claimed
   */
  function claimRewards(address _to) external returns (uint256 _rewardWeth, uint256 _rewardToken);

  /**
    @notice Adds a donation as a reward to be distributed among the lockers.
    @param  _wethAmount The amount of the donation in WETH sent to the lock manager
    @param  _tokenAmount The amount of the donation in non-WETH tokens sent to the lock manager
   */

  function addRewards(uint256 _wethAmount, uint256 _tokenAmount) external;

  // ********* CONCENTRATED POSITIONS ********* //

  /**
    @notice Returns the number of concentrated positions in this lock manager
    @return _positionsCount The number of concentrated positions
   */
  function getPositionsCount() external view returns (uint256 _positionsCount);

  /**
    @notice Get the the position that has to be minted
    @return _positionToMint The position that has to be minted
   */
  function getPositionToMint() external returns (IStrategy.LiquidityPosition memory _positionToMint);

  /**
    @notice Get the position to burn
    @param  _position The position to burn
    @return _positionToBurn The position that has to be burned
   */
  function getPositionToBurn(IStrategy.Position calldata _position) external returns (IStrategy.LiquidityPosition memory _positionToBurn);

  /**
    @notice Creates a concentrated WETH position
   */
  function mintPosition() external;

  /**
    @notice Burns a position that fell out of the active range
    @param  _position The position to be burned
   */
  function burnPosition(IStrategy.Position calldata _position) external;

  /**
    @notice Callback that is called when calling the mint method in a UniswapV3 pool
    @dev    It is only called in the creation of the full range and when positions need to be updated
    @param  _amount0Owed The amount of token0
    @param  _amount1Owed The amount of token1
    @param  _data not used
   */
  function uniswapV3MintCallback(
    uint256 _amount0Owed,
    uint256 _amount1Owed,
    bytes calldata _data
  ) external;

  /**
    @notice Returns an array of positions
    @param  _startFrom Index from where to start the pagination
    @param  _amount Maximum amount of positions to retrieve
    @return _positions The positions
   */
  function positionsList(uint256 _startFrom, uint256 _amount) external view returns (IStrategy.LiquidityPosition[] memory _positions);

  /**
    @notice Claims the fees from the UniswapV3 pool and stores them in the FeeManager
    @dev    Collects all available fees by passing type(uint128).max as requested amounts
    @param _positions The positions to claim the fees from
   */
  function collectFees(IStrategy.Position[] calldata _positions) external;

  /**
    @notice Burn the amount of lockedWeth provided by the caller
    @param  _lockedWethAmount The amount of lockedWeth to be burned
   */
  function burn(uint256 _lockedWethAmount) external;

  /**
    @notice Withdraws the corresponding part of WETH and non-WETH token depending on the locked WETH balance of the user and burns the lockTokens
    @dev    Only available if lockManager is deprecated and withdraws are enabled
    @param  _receiver The receiver of the tokens
   */
  function withdraw(address _receiver) external;

  /**
    @notice Unwinds a number of positions
    @dev    lockManager must be deprecated
    @param  _positions The number of positions to unwind from last to first
   */
  function unwind(uint256 _positions) external;
}
