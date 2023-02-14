// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.4 <0.9.0;

import 'isolmate/interfaces/tokens/IERC20.sol';

import '@interfaces/ILockManager.sol';

interface IBribe {
  /*///////////////////////////////////////////////////////////////
                              ERRORS
    //////////////////////////////////////////////////////////////*/

  /// @notice Thrown when the PoolManager is invalid
  error Bribe_InvalidPoolManager();

  /// @notice Thrown when the LockManager is invalid
  error Bribe_InvalidLockManager();

  /// @notice Throws when trying to create a Bribery with bribe Token having the zero address
  error Bribe_TokenZeroAddress();

  /// @notice Throws when trying to create a Bribery with 0 bribe amount
  error Bribe_AmountZero();

  /// @notice Throws when trying to withdraw but there is nothing deposited
  error Bribe_NothingToWithdraw();

  /// @notice Throws when trying to claim or update a user's balance with an invalid period
  error Bribe_InvalidPeriod();

  /// @notice Throws when trying to withdraw a bigger amount than deposited
  error Bribe_InvalidWithdrawAmount();

  /// @notice Throws when trying to update a user's balance but there is nothing to update
  error Bribe_NothingToUpdate();

  /*///////////////////////////////////////////////////////////////
                              EVENTS
    //////////////////////////////////////////////////////////////*/
  /**
    @notice              Emitted when someone creates a Bribery
    @param _lockManager  The LockManager that the Bribery targeted
    @param _bribeToken   The Token provided for the Bribery
    @param _bribeAmount  The total amount provided for the Bribery
    */
  event CreatedBribe(ILockManager _lockManager, IERC20 _bribeToken, uint256 _bribeAmount);

  /**
    @notice              Emitted when someones deposits an amount of LockManager to earn Bribery rewards
    @param _caller       The address that initiated the deposit
    @param _lockManager  The LockManager token
    @param _amount       The total amount of LockManager to deposit
    */
  event Deposit(address _caller, ILockManager _lockManager, uint256 _amount);

  /**
    @notice              Emitted when someones withdraws their LockManager
    @param _caller       The address that initiated the withdraw
    @param _lockManager  The LockManager token
    @param _amount       The total amount of LockManager that were withdrawn
    */
  event Withdraw(address _caller, ILockManager _lockManager, uint256 _amount);

  /**
    @notice              Emitted when someone claims the Bribery rewards
    @param _user         The address of the user that claimed the rewards
    @param _token        The token that got claimed
    @param _amount       The amount that got claimed
    */
  event ClaimedRewards(address _user, IERC20 _token, uint256 _amount);

  /**
    @notice              Emitted when someone updates manually their balances
    @param _user         The address of the user
    @param _lockManager  The LockManager to target
    @param _toPeriod     The end period to update
   */
  event UpdatedUserBalance(address _user, ILockManager _lockManager, uint256 _toPeriod);

  /*///////////////////////////////////////////////////////////////
                              STRUCTS
    //////////////////////////////////////////////////////////////*/

  /**
    @notice                         The Bribery Rewards information for a certain period
    @param start                    The block timestamp when the bribe starts
    @param end                      The block timestamp when the bribe end
    @param totalDeposited           The number of tokens total deposited by users
    @param bribeTokens              The token addresses of the rewards
    @param totalBribeAmountPerToken The amount of each token that will be distributed to lockers
    @param userBalance              The amount deposited by a user
    @param userHasClaimedToken      True if the user has claimed the rewards of a certain token of that period
    */
  struct PeriodRewards {
    uint256 start;
    uint256 end;
    uint256 totalDeposited;
    IERC20[] bribeTokens;
    mapping(IERC20 => uint256) totalBribeAmountPerToken;
    mapping(address => uint256) userBalance;
    mapping(address => mapping(IERC20 => bool)) userHasClaimedToken;
  }

  /*///////////////////////////////////////////////////////////////
                            VARIABLES
    //////////////////////////////////////////////////////////////*/

  /**
    @notice Returns the period when the user last interacted with a specific LockManager Bribe
    @param _user The address of the user to check
    @param _lockManager The LockManager to check
    @return _period The number of the period
    */
  function userLatestInteraction(address _user, ILockManager _lockManager) external view returns (uint256 _period);

  /**
    @notice                     Returns the contract PoolManagerFactory
    @return _poolManagerFactory The PoolManagerFactory
    */
  function POOL_MANAGER_FACTORY() external view returns (IPoolManagerFactory _poolManagerFactory);

  /*///////////////////////////////////////////////////////////////
                              LOGIC
    //////////////////////////////////////////////////////////////*/
  /**
    @notice              Creates and initializes a Bribery for a given LockManager
    @dev                 When a bribe is created we need to check if the previous finished or not
    @dev                 If it didn't then we have to add the tokens and amount to `nextBribe`
    @param _lockManager  The address of the LockManager token to create a Bribery for
    @param _bribeToken   The address of the Token to provide for the Bribery
    @param _bribeAmount  The total amount to provide for the Bribery
    */
  function createBribe(
    ILockManager _lockManager,
    IERC20 _bribeToken,
    uint256 _bribeAmount
  ) external;

  /**
    @notice              Deposits an amount of LockManager to earn bribes
    @param _lockManager  The address of the LockManager to deposit
    @param _amount       The amount to deposit
    */
  function deposit(ILockManager _lockManager, uint256 _amount) external;

  /**
    @notice              Withdraws LockManager tokens deposited by the user
    @param _lockManager  The address of the LockManager token to withdraw
    @param _amount       The amount to withdraw
    */
  function withdraw(ILockManager _lockManager, uint256 _amount) external;

  /**
    @notice             Updates the user's balance from the last time he interacted till the specified period
    @param _lockManager The LockManager to target
    @param _toPeriod    The period to update up to
   */
  function updateUserBalanceFromLastInteractionTo(ILockManager _lockManager, uint256 _toPeriod) external;

  /**
    @notice              Transfers the rewards of the Bribery to the caller for the specified tokens
    @param  _lockManager The address of the LockManager that the Bribery targets
    @param _tokens       The array of tokens that the user wants to claim
    @param _fromPeriod   The period to start claiming rewards from
    @param _toPeriod     The period to end claiming rewards from
  */
  function claimRewards(
    ILockManager _lockManager,
    IERC20[] memory _tokens,
    uint256 _fromPeriod,
    uint256 _toPeriod
  ) external;
}
