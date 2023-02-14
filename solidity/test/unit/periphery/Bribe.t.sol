// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import 'solidity-utils/test/DSTestPlus.sol';

import '@interfaces/ILockManager.sol';
import '@interfaces/periphery/IBribe.sol';
import '@contracts/periphery/Bribe.sol';

contract BribeForTest is Bribe {
  constructor(IPoolManagerFactory _poolManagerFactory) Bribe(_poolManagerFactory) {}

  function getPeriodInfo(ILockManager _lockManager, uint256 _periodIndex)
    public
    view
    returns (
      uint256 _start,
      uint256 _end,
      uint256 _totalDeposited,
      uint256 _numberOfTokens
    )
  {
    _start = periods[_lockManager][_periodIndex].start;
    _end = periods[_lockManager][_periodIndex].end;
    _totalDeposited = periods[_lockManager][_periodIndex].totalDeposited;
    _numberOfTokens = periods[_lockManager][_periodIndex].bribeTokens.length;
  }

  function getTokenAmountAtPeriod(
    ILockManager _lockManager,
    uint256 _periodIndex,
    IERC20 _token
  ) public view returns (uint256 _amount) {
    _amount = periods[_lockManager][_periodIndex].totalBribeAmountPerToken[_token];
  }

  function getUserBalanceAtPeriod(
    ILockManager _lockManager,
    uint256 _periodIndex,
    address _user
  ) public view returns (uint256 _amount) {
    _amount = periods[_lockManager][_periodIndex].userBalance[_user];
  }

  function getTotalDepositedAtPeriod(ILockManager _lockManager, uint256 _periodIndex) public view returns (uint256 _amount) {
    _amount = periods[_lockManager][_periodIndex].totalDeposited;
  }

  function getPeriodsArrayLength(ILockManager _lockManager) public view returns (uint256 _length) {
    _length = periods[_lockManager].length;
  }
}

abstract contract Base is DSTestPlus {
  IERC20 mockToken = IERC20(mockContract(address(200), 'mockToken'));
  IERC20 mockToken2 = IERC20(mockContract(address(201), 'mockToken'));
  ILockManager mockLockManager = ILockManager(mockContract(address(202), 'mockLockManager'));
  ILockManager mockLockManager2 = ILockManager(mockContract(address(203), 'mockLockManager2'));
  IPoolManagerFactory mockPoolManagerFactory = IPoolManagerFactory(mockContract(address(204), 'mockPoolManagerFactory'));
  IPoolManager mockPoolManager = IPoolManager(mockContract(address(205), 'mockPoolManager'));
  BribeForTest bribe;
  address user = address(100);

  function setUp() public virtual {
    vm.mockCall(address(mockLockManager), abi.encodeWithSelector(ILockManager.POOL_MANAGER.selector), abi.encode(mockPoolManager));
    vm.mockCall(address(mockPoolManager), abi.encodeWithSelector(IPoolManager.lockManager.selector), abi.encode(mockLockManager));
    vm.mockCall(
      address(mockPoolManagerFactory),
      abi.encodeWithSelector(IPoolManagerFactory.isChild.selector, mockPoolManager),
      abi.encode(true)
    );
    bribe = new BribeForTest(mockPoolManagerFactory);
  }
}

contract UnitConstructor is Base {
  function testSetParams() public {
    assertEq(address(bribe.POOL_MANAGER_FACTORY()), address(mockPoolManagerFactory));
  }
}

contract UnitBribeCreateBribe is Base {
  event CreatedBribe(ILockManager _lockManager, IERC20 _bribeToken, uint256 _bribeAmount);

  function testRevertIfInvalidPoolManager(uint256 _bribeAmount) public {
    vm.mockCall(
      address(mockPoolManagerFactory),
      abi.encodeWithSelector(IPoolManagerFactory.isChild.selector, mockPoolManager),
      abi.encode(false)
    );
    vm.expectRevert(IBribe.Bribe_InvalidPoolManager.selector);
    bribe.createBribe(mockLockManager, mockToken, _bribeAmount);
  }

  function testRevertIfInvalidLockManager(uint256 _bribeAmount) public {
    vm.mockCall(address(mockPoolManager), abi.encodeWithSelector(IPoolManager.lockManager.selector), abi.encode(mockLockManager2));
    vm.expectRevert(IBribe.Bribe_InvalidLockManager.selector);
    bribe.createBribe(mockLockManager, mockToken, _bribeAmount);
  }

  function testRevertIfInvalidBribeToken(uint256 _bribeAmount) public {
    vm.expectRevert(IBribe.Bribe_TokenZeroAddress.selector);
    bribe.createBribe(mockLockManager, IERC20(address(0)), _bribeAmount);
  }

  function testRevertIfInvalidBribeAmount() public {
    vm.expectRevert(IBribe.Bribe_AmountZero.selector);
    bribe.createBribe(mockLockManager, mockToken, 0);
  }

  function testCreateFirstBribeAndEmitEvent(uint256 _bribeAmount) public {
    vm.assume(_bribeAmount > 0);
    vm.expectEmit(false, false, false, true);
    vm.expectCall(address(mockToken), abi.encodeWithSelector(IERC20.transferFrom.selector, address(this), address(bribe), _bribeAmount));
    emit CreatedBribe(mockLockManager, mockToken, _bribeAmount);
    bribe.createBribe(mockLockManager, mockToken, _bribeAmount);
    (uint256 _start, uint256 _end, uint256 _deposited, uint256 _tokens) = bribe.getPeriodInfo(mockLockManager, 0);
    assertEq(bribe.getPeriodsArrayLength(mockLockManager), 1);
    assertEq(_start, block.timestamp);
    assertEq(_end, block.timestamp + 7 days);
    assertEq(_deposited, 0);
    assertEq(_tokens, 1);
  }

  function testCreateABribeDuringAnActiveOne(uint256 _bribeAmount) public {
    vm.assume(_bribeAmount > 0);
    /// 1st Bribe
    bribe.createBribe(mockLockManager, mockToken, _bribeAmount);
    /// 2nd Bribe
    vm.warp(block.timestamp + 1 days);
    bribe.createBribe(mockLockManager, mockToken, _bribeAmount);
    (, uint256 _endFirstBribe, , ) = bribe.getPeriodInfo(mockLockManager, 0);
    (uint256 _start, uint256 _end, uint256 _deposited, uint256 _tokens) = bribe.getPeriodInfo(mockLockManager, 1);
    assertEq(bribe.getPeriodsArrayLength(mockLockManager), 2);
    assertEq(_start, _endFirstBribe);
    assertEq(_end, _endFirstBribe + 7 days);
    assertEq(_deposited, 0);
    assertEq(_tokens, 1);
  }

  function testCreateABribeAfterThePreviousEnded(uint256 _bribeAmount) public {
    vm.assume(_bribeAmount > 0);
    /// 1st Bribe
    bribe.createBribe(mockLockManager, mockToken, _bribeAmount);
    /// 2nd Bribe
    vm.warp(block.timestamp + 10 days);
    bribe.createBribe(mockLockManager, mockToken, _bribeAmount);
    (uint256 _start, uint256 _end, uint256 _deposited, uint256 _tokens) = bribe.getPeriodInfo(mockLockManager, 1);
    assertEq(bribe.getPeriodsArrayLength(mockLockManager), 2);
    assertEq(_start, block.timestamp);
    assertEq(_end, block.timestamp + 7 days);
    assertEq(_deposited, 0);
    assertEq(_tokens, 1);
  }

  function testInitializeBribeIfCreatedByDeposit(uint256 _bribeAmount) public {
    vm.assume(_bribeAmount > 0);
    /// Creates the Period and stores and user's balance
    bribe.deposit(mockLockManager, 1 ether);
    bribe.createBribe(mockLockManager, mockToken, _bribeAmount);
    (uint256 _start, uint256 _end, uint256 _deposited, uint256 _tokens) = bribe.getPeriodInfo(mockLockManager, 0);
    assertEq(bribe.getPeriodsArrayLength(mockLockManager), 1);
    assertEq(_start, block.timestamp);
    assertEq(_end, block.timestamp + 7 days);
    assertEq(_deposited, 1 ether);
    assertEq(_tokens, 1);
  }

  function testInitializeNextBribeAndAddToExistingToken(uint256 _bribeAmount) public {
    vm.assume(_bribeAmount > 0 && _bribeAmount < type(uint256).max / 2);
    /// 1st Bribe normal create and initialize
    bribe.createBribe(mockLockManager, mockToken, _bribeAmount);
    vm.warp(block.timestamp + 1 days);
    /// 2nd Bribe created from deposit
    bribe.deposit(mockLockManager, 1 ether);
    /// 2nd Bribe initialized start/end and added rewards
    bribe.createBribe(mockLockManager, mockToken, _bribeAmount);
    uint256 _tokenAmount = bribe.getTokenAmountAtPeriod(mockLockManager, 1, mockToken);
    assertEq(_tokenAmount, _bribeAmount);
    /// 2nd Bribe add more tokens rewards
    bribe.createBribe(mockLockManager, mockToken, _bribeAmount);
    _tokenAmount = bribe.getTokenAmountAtPeriod(mockLockManager, 1, mockToken);
    assertEq(_tokenAmount, _bribeAmount * 2);
    (, uint256 _endFirstBribe, , ) = bribe.getPeriodInfo(mockLockManager, 0);
    (uint256 _start, uint256 _end, uint256 _deposited, uint256 _tokens) = bribe.getPeriodInfo(mockLockManager, 1);
    assertEq(bribe.getPeriodsArrayLength(mockLockManager), 2);
    assertEq(_start, _endFirstBribe);
    assertEq(_end, _endFirstBribe + 7 days);
    assertEq(_deposited, 1 ether);
    assertEq(_tokens, 1);
  }

  function testInitializeNextBribeAndAddNewToken(uint256 _bribeAmount) public {
    vm.assume(_bribeAmount > 0);
    /// 1st Bribe normal
    bribe.createBribe(mockLockManager, mockToken, _bribeAmount);
    vm.warp(block.timestamp + 1 days);
    /// 2nd Bribe created from deposit
    bribe.deposit(mockLockManager, 1 ether);
    /// 2nd Bribe initialized start/end and added rewards
    bribe.createBribe(mockLockManager, mockToken, _bribeAmount);
    uint256 _tokenAmount = bribe.getTokenAmountAtPeriod(mockLockManager, 1, mockToken);
    assertEq(_tokenAmount, _bribeAmount);
    /// 2nd Bribe add new token rewards
    bribe.createBribe(mockLockManager, mockToken2, _bribeAmount);
    _tokenAmount = bribe.getTokenAmountAtPeriod(mockLockManager, 1, mockToken2);
    assertEq(_tokenAmount, _bribeAmount);
    (, uint256 _endFirstBribe, , ) = bribe.getPeriodInfo(mockLockManager, 0);
    (uint256 _start, uint256 _end, uint256 _deposited, uint256 _tokens) = bribe.getPeriodInfo(mockLockManager, 1);
    assertEq(bribe.getPeriodsArrayLength(mockLockManager), 2);
    assertEq(_start, _endFirstBribe);
    assertEq(_end, _endFirstBribe + 7 days);
    assertEq(_deposited, 1 ether);
    assertEq(_tokens, 2);
  }
}

contract UnitBribeDeposit is Base {
  event Deposit(address _caller, ILockManager _lockManager, uint256 _amount);

  function testRevertIfInvalidAmount() public {
    vm.expectRevert(IBribe.Bribe_AmountZero.selector);
    bribe.deposit(mockLockManager, 0);
  }

  function testDepositAndEmitEvent(uint256 _amount) public {
    vm.assume(_amount > 0);
    vm.expectEmit(false, false, false, true);
    vm.expectCall(address(mockLockManager), abi.encodeWithSelector(IERC20.transferFrom.selector, user, address(bribe), _amount));
    emit Deposit(user, mockLockManager, _amount);
    vm.prank(user);
    bribe.deposit(mockLockManager, _amount);

    uint256 _periodIndexLastInteraction = bribe.userLatestInteraction(user, mockLockManager);
    uint256 _deposited = bribe.getUserBalanceAtPeriod(mockLockManager, 0, user);
    uint256 _totalDeposited = bribe.getTotalDepositedAtPeriod(mockLockManager, 0);
    assertEq(_periodIndexLastInteraction, 1);
    assertEq(_deposited, _amount);
    assertEq(_totalDeposited, _amount);
  }
}

contract UnitBribeWithdraw is Base {
  event Withdraw(address _caller, ILockManager _lockManager, uint256 _amount);

  function testRevertIfInvalidAmount() public {
    vm.expectRevert(IBribe.Bribe_AmountZero.selector);
    bribe.withdraw(mockLockManager, 0);
  }

  function testRevertIfNothingToWithdraw(uint256 _amount) public {
    vm.assume(_amount > 0);
    vm.expectRevert(IBribe.Bribe_NothingToWithdraw.selector);
    bribe.withdraw(mockLockManager, _amount);
  }

  function testRevertIfAmountGreaterThanDeposit(uint256 _amount) public {
    vm.assume(_amount > 1);
    bribe.deposit(mockLockManager, _amount / 2);
    vm.expectRevert(IBribe.Bribe_InvalidWithdrawAmount.selector);
    bribe.withdraw(mockLockManager, _amount);
  }

  function testWithdrawAndEmitEvent(uint256 _amount) public {
    vm.assume(_amount > 0);
    vm.prank(user);
    bribe.deposit(mockLockManager, _amount);
    vm.expectEmit(false, false, false, true);
    vm.expectCall(address(mockLockManager), abi.encodeWithSelector(IERC20.transfer.selector, user, _amount));
    emit Withdraw(user, mockLockManager, _amount);
    vm.prank(user);
    bribe.withdraw(mockLockManager, _amount);

    uint256 _deposited = bribe.getUserBalanceAtPeriod(mockLockManager, 0, user);
    uint256 _totalDeposited = bribe.getTotalDepositedAtPeriod(mockLockManager, 0);
    assertEq(_deposited, 0);
    assertEq(_totalDeposited, 0);
  }
}

contract UnitBribeClaimRewards is Base {
  event ClaimedRewards(address _user, IERC20 _token, uint256 _amount);

  function testRevertIfInvalidPeriod() public {
    vm.expectRevert(IBribe.Bribe_InvalidPeriod.selector);
    IERC20[] memory _token = new IERC20[](1);
    _token[0] = mockToken;
    bribe.claimRewards(mockLockManager, _token, 3, 2);
  }

  function testClaimRewards() public {
    vm.prank(user);
    /// Deposit before bribe
    bribe.deposit(mockLockManager, 1 ether);
    /// Create bribe
    bribe.createBribe(mockLockManager, mockToken, 10 ether);
    vm.warp(block.timestamp + 8 days);
    IERC20[] memory _token = new IERC20[](1);
    _token[0] = mockToken;

    vm.expectEmit(false, false, false, true);
    emit ClaimedRewards(user, mockToken, 10 ether);
    vm.expectCall(address(mockToken), abi.encodeWithSelector(IERC20.transfer.selector, user, 10 ether));
    /// Claim after period ended
    vm.prank(user);
    bribe.claimRewards(mockLockManager, _token, 1, 1);
  }
}

contract UnitUpdateUserRewards is Base {
  event UpdatedUserBalance(address _user, ILockManager _lockManager, uint256 _toPeriod);

  function testRevertIfInvalidPeriod(uint256 _toPeriod) public {
    vm.expectRevert(IBribe.Bribe_InvalidPeriod.selector);
    bribe.updateUserBalanceFromLastInteractionTo(mockLockManager, _toPeriod);
  }

  function testRevertIfThereIsNothingToUpdate() public {
    bribe.createBribe(mockLockManager, mockToken, 10 ether);
    vm.warp(block.timestamp + 8 days);
    bribe.createBribe(mockLockManager, mockToken, 10 ether);

    vm.expectRevert(IBribe.Bribe_NothingToUpdate.selector);
    bribe.updateUserBalanceFromLastInteractionTo(mockLockManager, 1);
  }

  function testUpdateUserBalanceAndEmitEvent() public {
    vm.prank(user);
    /// Deposit before bribe
    bribe.deposit(mockLockManager, 1 ether);
    /// Create bribe 1
    bribe.createBribe(mockLockManager, mockToken, 10 ether);
    vm.warp(block.timestamp + 8 days);
    /// Bribe 2
    bribe.createBribe(mockLockManager, mockToken, 10 ether);
    vm.warp(block.timestamp + 8 days);
    /// Brib 3
    bribe.createBribe(mockLockManager, mockToken, 10 ether);
    vm.warp(block.timestamp + 8 days);
    /// Bribe 4
    assertEq(bribe.getUserBalanceAtPeriod(mockLockManager, 2, user), 0);

    vm.expectEmit(false, false, false, true);
    emit UpdatedUserBalance(user, mockLockManager, 3);

    vm.prank(user);
    bribe.updateUserBalanceFromLastInteractionTo(mockLockManager, 3);
    assertEq(bribe.getUserBalanceAtPeriod(mockLockManager, 2, user), 1 ether);
  }
}
