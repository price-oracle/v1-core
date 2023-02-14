// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import 'solidity-utils/test/DSTestPlus.sol';

import '@contracts/utils/PRBMath.sol';
import '@contracts/LockManager.sol';
import '@contracts/periphery/LockedWethSecondaryMarket.sol';
import '@test/utils/TestConstants.sol';

abstract contract Base is DSTestPlus, TestConstants {
  IERC20 mockWeth = IERC20(mockContract(WETH_ADDRESS, 'mockWeth'));
  ILockManager lockedWeth = ILockManager(mockContract('mockLockManager'));
  IPoolManagerFactory poolManagerFactory = IPoolManagerFactory(mockContract('mockPoolManagerFactory'));
  IPoolManager poolManager = IPoolManager(mockContract('mockPoolManager'));
  ILockManager invalidLockedWeth = ILockManager(mockContract('mockLockManager2'));

  ILockedWethSecondaryMarket lockedWethSecondaryMarket;
  uint16 internal constant _DISCOUNT_PRECISION = 10_000;

  address locker = newAddress();
  address buyer = newAddress();

  function setUp() public virtual {
    mockPoolManagerCall(poolManager);
    mockLockManagerManagerCall(lockedWeth);
    mockPoolManagerIsChildCall(true);

    lockedWethSecondaryMarket = new LockedWethSecondaryMarket(poolManagerFactory, mockWeth);
  }

  function mockPoolManagerCall(IPoolManager _poolManager) internal {
    vm.mockCall(address(lockedWeth), abi.encodeWithSelector(ILockManager.POOL_MANAGER.selector), abi.encode(_poolManager));
  }

  function mockLockManagerManagerCall(ILockManager _lockManager) internal {
    vm.mockCall(address(poolManager), abi.encodeWithSelector(IPoolManager.lockManager.selector), abi.encode(_lockManager));
  }

  function mockPoolManagerIsChildCall(bool _isChild) internal {
    vm.mockCall(address(poolManagerFactory), abi.encodeWithSelector(IPoolManagerFactory.isChild.selector, poolManager), abi.encode(_isChild));
  }
}

contract UnitConstructor is Base {
  function testParamsSet() public {
    assertEq(address(lockedWethSecondaryMarket.POOL_MANAGER_FACTORY()), address(poolManagerFactory));
    assertEq(address(lockedWethSecondaryMarket.WETH()), address(mockWeth));
  }
}

contract UnitPostSellOrder is Base {
  event SellOrderPosted(ILockedWethSecondaryMarket.SellOrder _order);

  function testPostSellOrder(uint256 _amount, uint16 _discount) public {
    vm.assume(_amount > 0 && _discount <= _DISCOUNT_PRECISION);

    vm.prank(locker);
    lockedWethSecondaryMarket.postOrder(lockedWeth, _amount, _discount);

    (ILockManager _lockedWeth, uint256 _id, uint256 _orderAmount, address _owner, uint16 _orderDiscount) = lockedWethSecondaryMarket.sellOrders(
      1
    );

    assertEq(lockedWethSecondaryMarket.sellOrdersCount(), 1);
    assertEq(address(_lockedWeth), address(lockedWeth));
    assertEq(_id, 1);
    assertEq(_owner, locker);
    assertEq(_orderAmount, _amount);
    assertEq(_orderDiscount, _discount);
  }

  function testPostSellOrderEmitsEvent(uint256 _amount, uint16 _discount) public {
    vm.assume(_amount > 0 && _discount <= _DISCOUNT_PRECISION);

    ILockedWethSecondaryMarket.SellOrder memory _sellOrder = ILockedWethSecondaryMarket.SellOrder(lockedWeth, 1, _amount, locker, _discount);

    expectEmitNoIndex();
    emit SellOrderPosted(_sellOrder);

    vm.prank(locker);
    lockedWethSecondaryMarket.postOrder(lockedWeth, _amount, _discount);
  }

  function testRevertIfPostSellZeroOrderAmount(uint16 _discount) public {
    vm.assume(_discount <= _DISCOUNT_PRECISION);

    vm.expectRevert(ILockedWethSecondaryMarket.LockedWethSecondaryMarket_ZeroAmount.selector);
    lockedWethSecondaryMarket.postOrder(lockedWeth, 0, _discount);
  }

  function testRevertIfPostSellOrderDiscountExceedsMax(uint256 _amount, uint16 _discount) public {
    vm.assume(_amount > 0 && _discount > _DISCOUNT_PRECISION);

    //Assertion
    vm.expectRevert(
      abi.encodeWithSelector(ILockedWethSecondaryMarket.LockedWethSecondaryMarket_MaxDiscountExceeded.selector, _discount, _DISCOUNT_PRECISION)
    );
    lockedWethSecondaryMarket.postOrder(lockedWeth, _amount, _discount);
  }

  function testRevertIfInvalidPoolManager(uint256 _amount, uint16 _discount) public {
    vm.assume(_amount > 0 && _discount <= _DISCOUNT_PRECISION);

    mockPoolManagerIsChildCall(false);

    vm.expectRevert(abi.encodeWithSelector(ILockedWethSecondaryMarket.LockedWethSecondaryMarket_InvalidPoolManager.selector, poolManager));

    vm.prank(locker);
    lockedWethSecondaryMarket.postOrder(lockedWeth, _amount, _discount);
  }

  function testRevertIfInvalidLockManager(uint256 _amount, uint16 _discount) public {
    vm.assume(_amount > 0 && _discount <= _DISCOUNT_PRECISION);

    mockLockManagerManagerCall(invalidLockedWeth);

    vm.expectRevert(abi.encodeWithSelector(ILockedWethSecondaryMarket.LockedWethSecondaryMarket_InvalidLockManager.selector, lockedWeth));

    vm.prank(locker);
    lockedWethSecondaryMarket.postOrder(lockedWeth, _amount, _discount);
  }
}

contract UnitGetSellOrders is Base {
  function testGetSellOrders(uint256 _amount, uint16 _discount) public {
    vm.assume(_amount > 0 && _discount <= _DISCOUNT_PRECISION);
    vm.prank(locker);

    lockedWethSecondaryMarket.postOrder(lockedWeth, _amount, _discount);

    ILockedWethSecondaryMarket.SellOrder[] memory _sellOrders = lockedWethSecondaryMarket.getSellOrders(1, 1);
    ILockedWethSecondaryMarket.SellOrder memory _sellOrder = _sellOrders[0];

    assertEq(_sellOrders.length, 1);
    assertEq(_sellOrder.id, 1);
    assertEq(_sellOrder.owner, locker);
    assertEq(_sellOrder.amount, _amount);
    assertEq(_sellOrder.discount, _discount);
  }
}

contract UnitCancelOrder is Base {
  function testCancelOrder(uint256 _amount, uint16 _discount) public {
    vm.assume(_amount > 0 && _discount <= _DISCOUNT_PRECISION);
    vm.startPrank(locker);

    lockedWethSecondaryMarket.postOrder(lockedWeth, _amount, _discount);
    lockedWethSecondaryMarket.cancelOrder(1);
    vm.stopPrank();

    (ILockManager _lockedWeth, uint256 _id, uint256 _orderAmount, address _owner, uint16 _orderDiscount) = lockedWethSecondaryMarket.sellOrders(
      1
    );

    assertEq(address(_lockedWeth), address(0));
    assertEq(lockedWethSecondaryMarket.sellOrdersCount(), 1);
    assertEq(_id, 0);
    assertEq(_owner, address(0));
    assertEq(_orderAmount, 0);
    assertEq(_orderDiscount, 0);
  }

  function testRevertIfCancelOrderIfCallerIsNotOwner(uint256 _amount, uint16 _discount) public {
    vm.assume(_amount > 0 && _discount <= _DISCOUNT_PRECISION);
    vm.prank(locker);

    lockedWethSecondaryMarket.postOrder(lockedWeth, _amount, _discount);

    vm.expectRevert(abi.encodeWithSelector(ILockedWethSecondaryMarket.LockedWethSecondaryMarket_NotOrderOwner.selector, 1));
    lockedWethSecondaryMarket.cancelOrder(1);
    vm.stopPrank();
  }
}

contract UnitBuyOrder is Base {
  event SellOrderBought(ILockedWethSecondaryMarket.SellOrder _order, address _buyer);

  function testBuyOrder(uint128 _amount, uint16 _discount) public {
    vm.assume(_amount > 0 && _discount <= _DISCOUNT_PRECISION);
    uint256 _wethValue = _amount - PRBMath.mulDiv(_amount, _discount, _DISCOUNT_PRECISION);

    vm.mockCall(address(mockWeth), abi.encodeWithSelector(IERC20.transferFrom.selector, buyer, locker, _wethValue), abi.encode(true));
    vm.mockCall(address(lockedWeth), abi.encodeWithSelector(LockManager.transferFrom.selector, locker, buyer, _amount), abi.encode(true));

    vm.expectCall(address(mockWeth), abi.encodeWithSelector(IERC20.transferFrom.selector, buyer, locker, _wethValue));
    vm.expectCall(address(lockedWeth), abi.encodeWithSelector(LockManager.transferFrom.selector, locker, buyer, _amount));

    vm.prank(locker);
    lockedWethSecondaryMarket.postOrder(lockedWeth, _amount, _discount);
    vm.prank(buyer);
    lockedWethSecondaryMarket.buyOrder(1);

    (ILockManager _lockedWeth, uint256 _id, uint256 _orderAmount, address _owner, uint16 _orderDiscount) = lockedWethSecondaryMarket.sellOrders(
      1
    );

    assertEq(address(_lockedWeth), address(0));
    assertEq(lockedWethSecondaryMarket.sellOrdersCount(), 1);
    assertEq(_id, 0);
    assertEq(_owner, address(0));
    assertEq(_orderAmount, 0);
    assertEq(_orderDiscount, 0);
  }

  function testBuyOrderEmitsEvent(uint128 _amount, uint16 _discount) public {
    vm.assume(_amount > 0 && _discount <= _DISCOUNT_PRECISION);
    uint256 _wethValue = _amount - PRBMath.mulDiv(_amount, _discount, _DISCOUNT_PRECISION);

    vm.mockCall(address(mockWeth), abi.encodeWithSelector(IERC20.transferFrom.selector, buyer, locker, _wethValue), abi.encode(true));
    vm.mockCall(address(lockedWeth), abi.encodeWithSelector(LockManager.transferFrom.selector, locker, buyer, _amount), abi.encode(true));

    vm.prank(locker);
    lockedWethSecondaryMarket.postOrder(lockedWeth, _amount, _discount);

    ILockedWethSecondaryMarket.SellOrder memory _sellOrder = ILockedWethSecondaryMarket.SellOrder(lockedWeth, 1, _amount, locker, _discount);

    expectEmitNoIndex();
    emit SellOrderBought(_sellOrder, buyer);

    vm.prank(buyer);
    lockedWethSecondaryMarket.buyOrder(1);
  }

  function testRevertIfOrderWasCancelled(uint128 _amount, uint16 _discount) public {
    vm.assume(_amount > 0 && _discount <= _DISCOUNT_PRECISION);

    vm.startPrank(locker);
    lockedWethSecondaryMarket.postOrder(lockedWeth, _amount, _discount);
    lockedWethSecondaryMarket.cancelOrder(1);
    vm.stopPrank();

    vm.expectRevert(abi.encodeWithSelector(ILockedWethSecondaryMarket.LockedWethSecondaryMarket_OrderNotAvailable.selector, 1));

    vm.prank(buyer);
    lockedWethSecondaryMarket.buyOrder(1);
  }

  function testRevertIfOrderWasAlreadyBought(uint128 _amount, uint16 _discount) public {
    vm.assume(_amount > 0 && _discount <= _DISCOUNT_PRECISION);
    uint256 _wethValue = _amount - PRBMath.mulDiv(_amount, _discount, _DISCOUNT_PRECISION);

    vm.mockCall(address(mockWeth), abi.encodeWithSelector(IERC20.transferFrom.selector, buyer, locker, _wethValue), abi.encode(true));
    vm.mockCall(address(lockedWeth), abi.encodeWithSelector(LockManager.transferFrom.selector, locker, buyer, _amount), abi.encode(true));

    vm.prank(locker);
    lockedWethSecondaryMarket.postOrder(lockedWeth, _amount, _discount);

    vm.startPrank(buyer);
    lockedWethSecondaryMarket.buyOrder(1);

    vm.expectRevert(abi.encodeWithSelector(ILockedWethSecondaryMarket.LockedWethSecondaryMarket_OrderNotAvailable.selector, 1));
    lockedWethSecondaryMarket.buyOrder(1);
    vm.stopPrank();
  }
}
