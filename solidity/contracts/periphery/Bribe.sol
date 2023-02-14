// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.4 <0.9.0;

import '@contracts/utils/PRBMath.sol';
import 'isolmate/utils/SafeTransferLib.sol';
import '@interfaces/ILockManager.sol';
import '@interfaces/periphery/IBribe.sol';

contract Bribe is IBribe {
  using SafeTransferLib for IERC20;
  using SafeTransferLib for ILockManager;

  /// @notice Returns the array of all periods for a specific LockManager
  mapping(ILockManager => PeriodRewards[]) public periods;
  /// @inheritdoc IBribe
  mapping(address => mapping(ILockManager => uint256)) public userLatestInteraction;
  /// @inheritdoc IBribe
  IPoolManagerFactory public immutable POOL_MANAGER_FACTORY;
  /// @notice The number of days in a bribe period
  uint256 internal constant _PERIOD_DAYS = 7 days;
  /// @notice Used to calculate rewards with precision
  uint256 internal constant _BASE = 1 ether;

  constructor(IPoolManagerFactory _poolManagerFactory) {
    POOL_MANAGER_FACTORY = _poolManagerFactory;
  }

  /// @inheritdoc IBribe
  function createBribe(
    ILockManager _lockManager,
    IERC20 _bribeToken,
    uint256 _tokenAmount
  ) external {
    _checkLockManagerValidity(_lockManager);
    if (address(_bribeToken) == address(0)) revert Bribe_TokenZeroAddress();
    if (_tokenAmount == 0) revert Bribe_AmountZero();

    uint256 _periodsLength = periods[_lockManager].length;
    uint256 _lastPeriodStart;
    uint256 _lastPeriodEnd;
    /**
      If the periods array length is 0 then we initialize the first period that starts at `block.timestamp`
      and ends after `_PERIOD_DAYS`. Also add the token for the bribe into the period's `bribeTokens` array
      as well as send the bribe amount for that token
     */
    if (_periodsLength == 0) {
      periods[_lockManager].push();
      periods[_lockManager][_periodsLength].start = block.timestamp;
      periods[_lockManager][_periodsLength].end = block.timestamp + _PERIOD_DAYS;
      periods[_lockManager][_periodsLength].bribeTokens.push(_bribeToken);
      periods[_lockManager][_periodsLength].totalBribeAmountPerToken[_bribeToken] = _tokenAmount;
    } else {
      /**
        Else, there are already initialized periods for the LockManager, so we need to check, the moment
        of calling the function, if there is an active period or not and if the latest period is not initialized
        (in case it was created from deposit/withdraw)
       */
      _lastPeriodStart = periods[_lockManager][_periodsLength - 1].start;
      _lastPeriodEnd = periods[_lockManager][_periodsLength - 1].end;
      /**
        If the `block.timestamp` is higher than the last period starting time and the starting time is not 0
        then that means that we are in the middle of an active period or after the last period finished so
        in both cases we need to create the next period with the new bribe token and define the starting and ending
        time.
       */
      if (block.timestamp > _lastPeriodStart && _lastPeriodStart != 0) {
        periods[_lockManager].push();
        periods[_lockManager][_periodsLength].totalDeposited = periods[_lockManager][_periodsLength - 1].totalDeposited;
        /**
          If the `block.timestamp` is less that the period's end time that means the next period is gonna start
          right after the current one
         */
        if (block.timestamp < _lastPeriodEnd) {
          periods[_lockManager][_periodsLength].start = _lastPeriodEnd;
          periods[_lockManager][_periodsLength].end = _lastPeriodEnd + _PERIOD_DAYS;
        } else {
          /**
            Else, the last period has already finished, so start the new now
           */
          periods[_lockManager][_periodsLength].start = block.timestamp;
          periods[_lockManager][_periodsLength].end = block.timestamp + _PERIOD_DAYS;
        }
        periods[_lockManager][_periodsLength].bribeTokens.push(_bribeToken);
        periods[_lockManager][_periodsLength].totalBribeAmountPerToken[_bribeToken] = _tokenAmount;
      } else {
        /**
          Else, if we are here then it means the next period has been created from deposit/withdraw with
          non-initialized values for start and end period, OR the next period is initialized but hasn't started
          yet, which means we have to add the new bribe token to the next period's rewards
         */
        if (_lastPeriodStart == 0 && _lastPeriodEnd == 0) {
          /**
            First we cover the case where the next period is created but not initialized, here we have 2 options
            if the previous period hasn't finished then start it as soon as the previous ends
           */
          if (_periodsLength > 1) {
            uint256 _previousPeriodEnd = periods[_lockManager][_periodsLength - 2].end;
            periods[_lockManager][_periodsLength - 1].start = _previousPeriodEnd;
            periods[_lockManager][_periodsLength - 1].end = _previousPeriodEnd + _PERIOD_DAYS;
          } else {
            /**
              Else, it means the period has finished so start it right away
             */
            periods[_lockManager][_periodsLength - 1].start = block.timestamp;
            periods[_lockManager][_periodsLength - 1].end = block.timestamp + _PERIOD_DAYS;
          }
        }

        /**
          Update the rewards for next period, if the token doesn't exist add it, otherwise add the amount
          to the already existing one
         */
        if (periods[_lockManager][_periodsLength - 1].totalBribeAmountPerToken[_bribeToken] == 0) {
          periods[_lockManager][_periodsLength - 1].bribeTokens.push(_bribeToken);
          periods[_lockManager][_periodsLength - 1].totalBribeAmountPerToken[_bribeToken] = _tokenAmount;
        } else {
          periods[_lockManager][_periodsLength - 1].totalBribeAmountPerToken[_bribeToken] += _tokenAmount;
        }
      }
    }
    _bribeToken.safeTransferFrom(msg.sender, address(this), _tokenAmount);

    emit CreatedBribe(_lockManager, _bribeToken, _tokenAmount);
  }

  /// @inheritdoc IBribe
  function deposit(ILockManager _lockManager, uint256 _amount) external updateUserBalance(_lockManager, msg.sender) {
    /// TODO: transfer LockManager rewards and votes to msg.sender
    if (_amount == 0) revert Bribe_AmountZero();

    if (periods[_lockManager].length == 0) periods[_lockManager].push();

    uint256 _periodsLength = periods[_lockManager].length;
    uint256 _lastPeriodStart = periods[_lockManager][_periodsLength - 1].start;

    (uint256 _periodIndex, uint256 _balance, uint256 _totalDeposited, uint256 _lastInteractionPeriod) = _constructBribe(
      _lockManager,
      _periodsLength,
      _lastPeriodStart
    );

    if (block.timestamp > _lastPeriodStart && _lastPeriodStart != 0) {
      periods[_lockManager].push();
    }

    periods[_lockManager][_periodIndex].userBalance[msg.sender] = _balance + _amount;
    periods[_lockManager][_periodIndex].totalDeposited = _totalDeposited + _amount;
    userLatestInteraction[msg.sender][_lockManager] = _lastInteractionPeriod;

    _lockManager.safeTransferFrom(msg.sender, address(this), _amount);

    emit Deposit(msg.sender, _lockManager, _amount);
  }

  /// @inheritdoc IBribe
  function withdraw(ILockManager _lockManager, uint256 _amount) external updateUserBalance(_lockManager, msg.sender) {
    /// TODO: Add check for LockManager deprecation, from LockManagerGovernor?
    if (_amount == 0) revert Bribe_AmountZero();

    uint256 _periodsLength = periods[_lockManager].length;
    uint256 _periodIdLastInteraction = userLatestInteraction[msg.sender][_lockManager];
    if (_periodsLength == 0 || _periodIdLastInteraction == 0) revert Bribe_NothingToWithdraw();

    uint256 _userBalance = periods[_lockManager][_periodIdLastInteraction - 1].userBalance[msg.sender];
    if (_userBalance < _amount) revert Bribe_InvalidWithdrawAmount();

    uint256 _lastPeriodStart = periods[_lockManager][_periodsLength - 1].start;

    (uint256 _periodIndex, , uint256 _totalDeposited, uint256 _lastInteractionPeriod) = _constructBribe(
      _lockManager,
      _periodsLength,
      _lastPeriodStart
    );

    if (block.timestamp > _lastPeriodStart && _lastPeriodStart != 0) {
      periods[_lockManager].push();
    }

    periods[_lockManager][_periodIndex].userBalance[msg.sender] = _userBalance - _amount;
    periods[_lockManager][_periodIndex].totalDeposited = _totalDeposited - _amount;
    userLatestInteraction[msg.sender][_lockManager] = _lastInteractionPeriod;

    _lockManager.safeTransfer(msg.sender, _amount);

    emit Withdraw(msg.sender, _lockManager, _amount);
  }

  /// @inheritdoc IBribe
  function claimRewards(
    ILockManager _lockManager,
    IERC20[] calldata _tokens,
    uint256 _fromPeriod,
    uint256 _toPeriod
  ) external updateUserBalance(_lockManager, msg.sender) {
    uint256 _periodsLength = periods[_lockManager].length;
    if (_fromPeriod == 0 || _toPeriod == 0 || _periodsLength < _toPeriod || _periodsLength < _fromPeriod) revert Bribe_InvalidPeriod();
    uint256[] memory _rewards = _calculateRewards(_lockManager, _tokens, _fromPeriod, _toPeriod);
    for (uint256 _i = 0; _i < _rewards.length; _i++) {
      if (_rewards[_i] != 0) _tokens[_i].safeTransfer(msg.sender, _rewards[_i]);
      emit ClaimedRewards(msg.sender, _tokens[_i], _rewards[_i]);
    }
  }

  /// @inheritdoc IBribe
  function updateUserBalanceFromLastInteractionTo(ILockManager _lockManager, uint256 _toPeriod) external {
    _checkLockManagerValidity(_lockManager);
    uint256 _periodsLength = periods[_lockManager].length;
    if (_toPeriod > _periodsLength || _toPeriod == 0) revert Bribe_InvalidPeriod();
    uint256 _lastPeriodUpdate = userLatestInteraction[msg.sender][_lockManager];

    if (_lastPeriodUpdate == 0 || _lastPeriodUpdate >= _toPeriod) revert Bribe_NothingToUpdate();

    uint256 _userBalanceAtLastUpdate = periods[_lockManager][_lastPeriodUpdate - 1].userBalance[msg.sender];
    for (uint256 _i = _lastPeriodUpdate; _i < _toPeriod; _i++) {
      periods[_lockManager][_i].userBalance[msg.sender] = _userBalanceAtLastUpdate;
    }

    userLatestInteraction[msg.sender][_lockManager] = _toPeriod;
    emit UpdatedUserBalance(msg.sender, _lockManager, _toPeriod);
  }

  /**
    @notice Calculates the rewards of a token between 2 periods
    @param _lockManager The LockManager to target
    @param _tokens      The tokens to calculate rewards for
    @param _fromPeriod  The index to start claiming
    @param _toPeriod    The index to finish claiming
    @return _amounts    The total amount of _tokens that can be claimed between _fromPeriod till _toPeriod
    */
  function _calculateRewards(
    ILockManager _lockManager,
    IERC20[] calldata _tokens,
    uint256 _fromPeriod,
    uint256 _toPeriod
  ) internal returns (uint256[] memory _amounts) {
    _amounts = new uint256[](_tokens.length);
    uint256 _userBalance;
    uint256 _totalDeposited;
    uint256 _userShares;
    uint256 _totalBribeAmountPerToken;
    bool _hasClaimed;
    for (uint256 _i = _fromPeriod - 1; _i < _toPeriod; _i++) {
      _userBalance = periods[_lockManager][_i].userBalance[msg.sender];
      _totalDeposited = periods[_lockManager][_i].totalDeposited;
      _userShares = PRBMath.mulDiv(_BASE, _userBalance, _totalDeposited);
      for (uint256 _j = 0; _j < _tokens.length; _j++) {
        _totalBribeAmountPerToken = periods[_lockManager][_i].totalBribeAmountPerToken[_tokens[_j]];
        _hasClaimed = periods[_lockManager][_i].userHasClaimedToken[msg.sender][_tokens[_j]];
        if (_totalBribeAmountPerToken != 0 && _userBalance != 0 && !_hasClaimed) {
          _amounts[_j] += PRBMath.mulDiv(_userShares, _totalBribeAmountPerToken, _BASE);
          periods[_lockManager][_i].userHasClaimedToken[msg.sender][_tokens[_j]] = true;
        }
      }
    }
  }

  /**
   @notice Returns bribe information for next period when depositing/withdrawing
   @param _lockManager The LockManager to target
   @param _length The periods array length
   @param _start The starting time of the last period
   @return _periodIndex The index of the period to update from the periods array
   @return _balance The balance of the user at the period
   @return _totalDeposited The total deposited for the period
   @return _lastInteractionPeriod The period index where the user last interacted
   */
  function _constructBribe(
    ILockManager _lockManager,
    uint256 _length,
    uint256 _start
  )
    internal
    view
    returns (
      uint256 _periodIndex,
      uint256 _balance,
      uint256 _totalDeposited,
      uint256 _lastInteractionPeriod
    )
  {
    /// If blocktimestamp is between the current period then we need to create a new period
    /// and save the users new balance there
    _balance = periods[_lockManager][_length - 1].userBalance[msg.sender];
    _totalDeposited = periods[_lockManager][_length - 1].totalDeposited;
    if (block.timestamp > _start && _start != 0) {
      _periodIndex = _length;
      _lastInteractionPeriod = _length + 1;
      /// ELSE means that the new period has been initialized and not started so just add to balance
    } else {
      _periodIndex = _length - 1;
      _lastInteractionPeriod = _length;
    }
  }

  /**
    @notice Checks if a given LockManager is valid
    @param _lockManager The LockManager to check
    */
  function _checkLockManagerValidity(ILockManager _lockManager) private view {
    IPoolManager _poolManager = _lockManager.POOL_MANAGER();
    ILockManager _lockManagerFromPoolManager = _poolManager.lockManager();

    if (!POOL_MANAGER_FACTORY.isChild(_poolManager)) revert Bribe_InvalidPoolManager();
    if (_lockManagerFromPoolManager != _lockManager) revert Bribe_InvalidLockManager();
  }

  /**
    @notice Modifier is called everytime a user interacts with the contract deposit/withdraw/claim
            and updates the user's balances from the last time he interacted till the latest period
    @param _lockManager The LockManager to target
    @param _user        The user's address
   */
  modifier updateUserBalance(ILockManager _lockManager, address _user) {
    _checkLockManagerValidity(_lockManager);
    uint256 _periodsLength = periods[_lockManager].length;
    if (_periodsLength != 0) {
      uint256 _lastPeriodUpdate = userLatestInteraction[_user][_lockManager];
      if (_lastPeriodUpdate != 0 && _lastPeriodUpdate < _periodsLength) {
        uint256 _userBalanceAtLastUpdate = periods[_lockManager][_lastPeriodUpdate - 1].userBalance[_user];
        for (uint256 i = _lastPeriodUpdate; i < _periodsLength; i++) {
          periods[_lockManager][i].userBalance[_user] = _userBalanceAtLastUpdate;
        }
      }
    }
    _;
  }
}
