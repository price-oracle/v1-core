// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.4 <0.9.0;

import 'isolmate/utils/SafeTransferLib.sol';
import '@contracts/utils/PRBMath.sol';
import '@interfaces/periphery/ILockedWethSecondaryMarket.sol';

contract LockedWethSecondaryMarket is ILockedWethSecondaryMarket {
  using SafeTransferLib for ILockManager;
  using SafeTransferLib for IERC20;

  /// _orderId => _sellOrder
  /// @inheritdoc ILockedWethSecondaryMarket
  mapping(uint256 => SellOrder) public sellOrders;

  /// @inheritdoc ILockedWethSecondaryMarket
  uint256 public sellOrdersCount;

  /**
    @notice Discount precision
   */
  uint16 private constant _DISCOUNT_PRECISION = 10_000;

  /// @inheritdoc ILockedWethSecondaryMarket
  IPoolManagerFactory public immutable POOL_MANAGER_FACTORY;

  /// @inheritdoc ILockedWethSecondaryMarket
  IERC20 public immutable WETH;

  constructor(IPoolManagerFactory _poolManagerFactory, IERC20 _weth) {
    POOL_MANAGER_FACTORY = _poolManagerFactory;
    WETH = _weth;
  }

  /// @inheritdoc ILockedWethSecondaryMarket
  function getSellOrders(uint256 _startFrom, uint256 _amount) external view returns (SellOrder[] memory _orders) {
    _orders = new SellOrder[](_amount);
    for (uint256 _i; _i < _amount; ++_i) {
      _orders[_i] = sellOrders[_startFrom + _i];
    }
  }

  /// @inheritdoc ILockedWethSecondaryMarket
  function postOrder(
    ILockManager _lockedWethToken,
    uint256 _amount,
    uint16 _discount
  ) external override {
    _checkLockManagerValidity(_lockedWethToken);

    if (_amount == 0) revert LockedWethSecondaryMarket_ZeroAmount();
    if (_discount > _DISCOUNT_PRECISION) revert LockedWethSecondaryMarket_MaxDiscountExceeded(_discount, _DISCOUNT_PRECISION);

    //We will always start with orderId == 1, orderId == 0 will never exist
    uint256 _orderId = sellOrdersCount + 1;
    SellOrder memory _order = SellOrder({
      lockedWethToken: _lockedWethToken,
      id: _orderId,
      amount: _amount,
      owner: msg.sender,
      discount: _discount
    });
    sellOrders[_orderId] = _order;
    sellOrdersCount = _orderId;

    emit SellOrderPosted(_order);
  }

  /// @inheritdoc ILockedWethSecondaryMarket
  function cancelOrder(uint256 _orderId) external onlyOrderOwner(_orderId) {
    SellOrder memory _order = sellOrders[_orderId];
    delete sellOrders[_orderId];
    emit SellOrderCancelled(_order);
  }

  /// @inheritdoc ILockedWethSecondaryMarket
  function buyOrder(uint256 _orderId) external {
    SellOrder memory _order = sellOrders[_orderId];

    if (_order.amount == 0) revert LockedWethSecondaryMarket_OrderNotAvailable(_orderId);

    // Checks if the lock manager is not deprecated
    ILockManager _lockedWeth = _order.lockedWethToken;
    _checkLockManagerValidity(_lockedWeth);

    uint256 _wethValue = _order.amount - PRBMath.mulDiv(_order.amount, _order.discount, _DISCOUNT_PRECISION);

    delete sellOrders[_orderId];

    WETH.safeTransferFrom(msg.sender, _order.owner, _wethValue);
    _lockedWeth.safeTransferFrom(_order.owner, msg.sender, _order.amount);

    emit SellOrderBought(_order, msg.sender);
  }

  /**
    @notice Checks if the provided lock manager is valid, otherwise it reverts
    @dev    Gets the pool manager and checks if it is a child of the pool manager's factory
              and if it is the same as the one provided in the method parameter
              Fetching the lock manager from the pool manager is necessary to ensure the function
              wasn't called from a malicious contract returning a valid pool manager
    @param  _lockManager The LockManager to check
   */
  function _checkLockManagerValidity(ILockManager _lockManager) private view {
    IPoolManager _poolManager = _lockManager.POOL_MANAGER();
    ILockManager _lockManagerFromPoolManager = _poolManager.lockManager();

    if (!POOL_MANAGER_FACTORY.isChild(_poolManager)) revert LockedWethSecondaryMarket_InvalidPoolManager(_poolManager);
    if (_lockManagerFromPoolManager != _lockManager) revert LockedWethSecondaryMarket_InvalidLockManager(_lockManager);
  }

  /*///////////////////////////////////////////////////////////////
                              MODIFIERS
  //////////////////////////////////////////////////////////////*/
  /**
    @notice Functions with this modifier can only be called by the owner of the sell order
   */
  modifier onlyOrderOwner(uint256 _orderId) {
    if (msg.sender != sellOrders[_orderId].owner) revert LockedWethSecondaryMarket_NotOrderOwner(_orderId);
    _;
  }
}
