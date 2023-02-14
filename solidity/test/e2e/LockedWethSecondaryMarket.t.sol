// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '@contracts/utils/PRBMath.sol';
import '@test/e2e/Common.sol';

contract E2ELockedWethSecondaryMarket is CommonE2EBase {
  uint16 internal constant _DISCOUNT_PRECISION = 10_000;

  function testE2EPostMultipleOrders(
    uint256 _amount,
    uint16 _discount,
    uint256 _amount2,
    uint16 _discount2
  ) public {
    vm.assume(_amount > 0 && _amount <= weth.balanceOf(address(user1)) && _discount <= _DISCOUNT_PRECISION);
    vm.assume(_amount2 > 0 && _amount2 <= weth.balanceOf(address(user2)) && _discount2 <= _DISCOUNT_PRECISION);

    vm.startPrank(address(user1));
    lockedWethSecondaryMarket.postOrder(lockManager, _amount, _discount);

    (ILockManager _lockedWeth, uint256 _id, uint256 _orderAmount, address _owner, uint16 _orderDiscount) = lockedWethSecondaryMarket.sellOrders(
      1
    );

    /// Assertions
    assertEq(lockedWethSecondaryMarket.sellOrdersCount(), 1);
    assertEq(address(_lockedWeth), address(lockManager));
    assertEq(_id, 1);
    assertEq(_owner, user1);
    assertEq(_orderAmount, _amount);
    assertEq(_orderDiscount, _discount);

    vm.stopPrank();
    vm.startPrank(user2);
    lockedWethSecondaryMarket.postOrder(lockManager, _amount2, _discount2);

    (ILockManager _lockedWeth2, uint256 _id2, uint256 _orderAmount2, address _owner2, uint16 _orderDiscount2) = lockedWethSecondaryMarket
      .sellOrders(2);

    assertEq(lockedWethSecondaryMarket.sellOrdersCount(), 2);
    assertEq(address(_lockedWeth2), address(lockManager));
    assertEq(_id2, 2);
    assertEq(_owner2, user2);
    assertEq(_orderAmount2, _amount2);
    assertEq(_orderDiscount2, _discount2);
  }

  function testE2EPostAndBuySellOrderFlow(uint256 _amount, uint16 _discount) public {
    vm.assume(_amount > 0 && _amount <= weth.balanceOf(address(user1)) && _discount <= _DISCOUNT_PRECISION);

    _lockWeth(address(user1), weth.balanceOf(address(user1)));
    uint256 previousUser1WethBalance = weth.balanceOf(address(user1));
    uint256 previousUser1LockedWethBalance = lockManager.balanceOf(address(user1));

    // Post order only set an order available and public
    vm.startPrank(address(user1));
    lockedWethSecondaryMarket.postOrder(lockManager, _amount, _discount);

    // In order to let the sell order executed the allowance for locked WETH need to be set
    lockManager.approve(address(lockedWethSecondaryMarket), _amount);
    vm.stopPrank();

    vm.startPrank(user2);
    uint256 _wethValue = _amount - PRBMath.mulDiv(_amount, _discount, _DISCOUNT_PRECISION);

    // In order to let the sell order executed the allowance for WETH token need to be set
    weth.approve(address(lockedWethSecondaryMarket), _wethValue);
    uint256 previousUser2WethBalance = weth.balanceOf(address(user2));

    lockedWethSecondaryMarket.buyOrder(1);
    vm.stopPrank();

    (ILockManager _lockedWeth, uint256 _id, uint256 _orderAmount, address _owner, uint16 _orderDiscount) = lockedWethSecondaryMarket.sellOrders(
      1
    );

    // Assertions
    assertEq(lockManager.balanceOf(user2), _amount);
    assertEq(lockManager.balanceOf(user1), previousUser1LockedWethBalance - _amount);
    assertEq(weth.balanceOf(user1), previousUser1WethBalance + _wethValue);
    assertEq(weth.balanceOf(user2), previousUser2WethBalance - _wethValue);

    assertEq(address(_lockedWeth), address(0));
    assertEq(lockedWethSecondaryMarket.sellOrdersCount(), 1);
    assertEq(_id, 0);
    assertEq(_owner, address(0));
    assertEq(_orderAmount, 0);
    assertEq(_orderDiscount, 0);
  }

  function testE2EPostAndCancelSellOrderFlow(uint256 _amount, uint16 _discount) public {
    vm.assume(_amount > 0 && _discount <= _DISCOUNT_PRECISION);

    // Post order only set an order available and public
    vm.startPrank(address(user1));
    lockedWethSecondaryMarket.postOrder(lockManager, _amount, _discount);
    lockedWethSecondaryMarket.cancelOrder(1);
    vm.stopPrank();

    (ILockManager _lockedWeth, uint256 _id, uint256 _orderAmount, address _owner, uint16 _orderDiscount) = lockedWethSecondaryMarket.sellOrders(
      1
    );

    /// Assertions
    assertEq(address(_lockedWeth), address(0));
    assertEq(lockedWethSecondaryMarket.sellOrdersCount(), 1);
    assertEq(_id, 0);
    assertEq(_owner, address(0));
    assertEq(_orderAmount, 0);
    assertEq(_orderDiscount, 0);
  }
}
