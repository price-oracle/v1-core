// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.4 <0.9.0;

import '@interfaces/ILockManager.sol';

/**
  @title LockedWethSecondaryMarket contract
  @notice This contract manages LockedWeth tokens sell orders
 */
interface ILockedWethSecondaryMarket {
  /*///////////////////////////////////////////////////////////////
                              ERRORS
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Thrown when the pool manager is invalid
   */
  error LockedWethSecondaryMarket_InvalidPoolManager(IPoolManager _poolManager);

  /**
    @notice Thrown when the lock manager is invalid
   */
  error LockedWethSecondaryMarket_InvalidLockManager(ILockManager _lockManager);

  /**
    @notice Thrown when the order amount is zero
   */
  error LockedWethSecondaryMarket_ZeroAmount();

  /**
    @notice Thrown when the discount value exceeds the max discount
    @param  _discount The invalid discount value
    @param  _maxDiscount The max discount value allowed
   */
  error LockedWethSecondaryMarket_MaxDiscountExceeded(uint16 _discount, uint16 _maxDiscount);

  /**
    @notice Thrown when trying to delete an order and the caller is not the owner
    @param  _orderId The id of the order
   */
  error LockedWethSecondaryMarket_NotOrderOwner(uint256 _orderId);

  /**
    @notice Thrown when trying to buy a sell order whose amount is zero
    @dev    The order could not be available because it was already sold or canceled
    @param  _orderId The order's id used to call the buy function
   */
  error LockedWethSecondaryMarket_OrderNotAvailable(uint256 _orderId);

  /*///////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Emitted when a new LockedWeth sell order is posted
    @param  _order The sell order posted
   */
  event SellOrderPosted(SellOrder _order);

  /**
    @notice Emitted when a sell order is bought
    @param  _order The order bought
    @param  _buyer The address of the account that purchased the order
   */
  event SellOrderBought(SellOrder _order, address _buyer);

  /**
    @notice Emitted when a sell order is canceled
    @param  _order The order canceled
   */
  event SellOrderCancelled(SellOrder _order);

  /*///////////////////////////////////////////////////////////////
                            VARIABLES
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Returns the WETH contract
    @return _weth The WETH token
   */
  function WETH() external view returns (IERC20 _weth);

  /**
    @notice Returns the pool manager factory contract
    @return _poolManagerFactory The pool manager factory
   */
  function POOL_MANAGER_FACTORY() external view returns (IPoolManagerFactory _poolManagerFactory);

  /**
    @notice Returns a sell order
    @param  _orderId The order id
   */
  function sellOrders(uint256 _orderId)
    external
    view
    returns (
      ILockManager _lockedWethToken,
      uint256 _id,
      uint256 _amount,
      address _owner,
      uint16 _discount
    );

  /**
    @notice Returns the sell orders count
    @return _sellOrdersCount The sell orders count
   */
  function sellOrdersCount() external view returns (uint256 _sellOrdersCount);

  /*///////////////////////////////////////////////////////////////
                            LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Posts a LockedWeth sell limit order
    @dev    The amount is represented in WETH tokens
            The LockedWeth tokens remain in the poster account
            The discount value must be less than the discount precision
    @param  _lockedWethToken The locked WETH
    @param  _amount The amount of LockedWeth tokens to be sold
    @param  _discount The discount value
   */
  function postOrder(
    ILockManager _lockedWethToken,
    uint256 _amount,
    uint16 _discount
  ) external;

  /**
    @notice Buys a sell order
    @dev    The sell order is bought with WETH tokens and cannot be purchased partially
    @param  _orderId The id of the sell order to be bought
   */
  function buyOrder(uint256 _orderId) external;

  /**
    @notice Cancels a sell order
    @dev    The caller must be the order owner
    @param  _orderId The id of the order to be canceled
   */
  function cancelOrder(uint256 _orderId) external;

  /**
    @notice Returns pagination of the orders posted
    @dev    Minimum _startFrom is 1; ids start from 1
    @param  _startFrom The index from where to start the pagination
    @param  _amount The maximum amount of orders to retrieve
    @return _sellOrders The paginated orders posted
   */
  function getSellOrders(uint256 _startFrom, uint256 _amount) external returns (SellOrder[] memory _sellOrders);

  /*///////////////////////////////////////////////////////////////
                              STRUCTS
  //////////////////////////////////////////////////////////////*/

  /**
    @notice The sell order
    @param  owner The address that posted the order
    @param  amount The amount of LockedWeth tokens to sell
    @param  discount The discount amount
   */
  struct SellOrder {
    ILockManager lockedWethToken;
    uint256 id;
    uint256 amount;
    address owner;
    uint16 discount;
  }
}
