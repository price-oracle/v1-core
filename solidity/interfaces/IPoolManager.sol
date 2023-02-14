// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.4 <0.9.0;

import 'isolmate/interfaces/tokens/IERC20.sol';
import 'uni-v3-core/interfaces/IUniswapV3Pool.sol';
import 'uni-v3-core/interfaces/IUniswapV3Factory.sol';

import '@interfaces/IPoolManagerGovernor.sol';
import '@interfaces/IPoolManagerFactory.sol';
import '@interfaces/IFeeManager.sol';
import '@interfaces/ILockManager.sol';
import '@interfaces/strategies/IStrategy.sol';

/**
  @title PoolManager contract
  @notice This contract manages the protocol owned positions of the associated uni v3 pool
 */
interface IPoolManager is IPoolManagerGovernor {
  /*///////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Emitted when a seeder burns liquidity
    @param  _liquidity The liquidity that has been burned
   */
  event SeederLiquidityBurned(uint256 _liquidity);

  /**
    @notice Emitted when a lock manager is deprecated
    @param  _oldLockManager The lock manager that was deprecated
    @param  _newLockManager The new lock manager
   */
  event LockManagerDeprecated(ILockManager _oldLockManager, ILockManager _newLockManager);

  /**
    @notice Emitted when fees are collected
    @param  _totalFeeWeth Total WETH amount collected
    @param  _totalFeeToken Total token amount collected
   */
  event FeesCollected(uint256 _totalFeeWeth, uint256 _totalFeeToken);

  /**
    @notice Emitted when rewards are added to a pool manager
    @param  _wethAmount The amount of WETH added
    @param  _tokenAmount The amount of WETH added
   */
  event RewardsAdded(uint256 _wethAmount, uint256 _tokenAmount);

  /**
    @notice Emitted when a seeder claims their rewards
    @param  _user The address of the user that claimed the rewards
    @param  _wethAmount The amount of WETH tokens to claim
    @param  _tokenAmount The amount of non-WETH tokens to claim
   */
  event ClaimedRewards(address _user, address _to, uint256 _wethAmount, uint256 _tokenAmount);

  /*///////////////////////////////////////////////////////////////
                              ERRORS
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Thrown when someone other than the factory tries to call the method
   */
  error PoolManager_OnlyFactory();

  /**
    @notice Thrown when someone other than the pool tries to call the method
   */
  error PoolManager_OnlyPool();

  /**
    @notice Thrown when someone tries to deploy a new lock manager while the old one is still not deprecated
   */
  error PoolManager_ActiveLockManager();

  /**
    @notice Thrown when the amount is zero
   */
  error PoolManager_ZeroAmount();

  /**
    @notice Thrown when the provided address is zero
   */
  error PoolManager_ZeroAddress();

  /**
    @notice Thrown when the user doesn't have rewards to claim
   */
  error PoolManager_NoRewardsToClaim();

  /**
    @notice Thrown when the price oracle detects a manipulation
   */
  error PoolManager_PoolManipulated();

  /**
    @notice Thrown when the FeeManager provided is incorrect
   */
  error PoolManager_InvalidFeeManager();

  /**
    @notice Thrown when the caller of the `burn1` function is not the current oracle
   */
  error PoolManager_InvalidPriceOracle();

  /*///////////////////////////////////////////////////////////////
                              STRUCTS
  //////////////////////////////////////////////////////////////*/

  /**
    @notice The amounts of paid and available rewards per seeder
    @param  wethPaid The WETH amount already claimed
    @param  tokenPaid The non-WETH token amount already claimed
    @param  wethAvailable The available WETH amount
    @param  tokenAvailable The available non-WETH token amount
   */
  struct SeederRewards {
    uint256 wethPaid;
    uint256 tokenPaid;
    uint256 wethAvailable;
    uint256 tokenAvailable;
  }

  /**
    @notice Pool status for internal accountancy
    @param  wethPerSeededLiquidity The value of the reward per WETH locked
    @param  tokenPerSeededLiquidity The value of the reward per non-WETH token locked
   */
  struct PoolRewards {
    uint256 wethPerSeededLiquidity;
    uint256 tokenPerSeededLiquidity;
  }

  /**
    @notice The parameters for the lock manager
   */
  struct LockManagerParams {
    IPoolManagerFactory factory;
    IStrategy strategy;
    IERC20 token;
    IERC20 weth;
    IUniswapV3Pool pool;
    bool isWethToken0;
    uint24 fee;
    address governance;
    uint256 index;
  }

  /**
    @notice UniswapV3 pool position
    @param  lowerTick The lower tick of the position
    @param  upperTick The upper tick of the position
   */
  struct Position {
    int24 lowerTick;
    int24 upperTick;
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
    @notice Returns the UniswapV3 factory contract
    @return _uniswapV3Factory The UniswapV3 factory contract
   */
  function UNISWAP_V3_FACTORY() external view returns (IUniswapV3Factory _uniswapV3Factory);

  /**
    @notice Returns the UniswapV3 pool bytecode hash
    @return _poolBytecodeHash The UniswapV3 pool bytecode hash
   */
  function POOL_BYTECODE_HASH() external view returns (bytes32 _poolBytecodeHash);

  /**
    @notice Returns the lock manager contract
    @return _lockManager The lock manager
   */
  function lockManager() external view returns (ILockManager _lockManager);

  /**
    @notice Returns a deprecated lock manager contract at a specific index
    @return _deprecatedLockManagers A deprecated lock manager
   */
  function deprecatedLockManagers(uint256 _index) external view returns (ILockManager _deprecatedLockManagers);

  /**
    @notice Returns the fee of the pool manager
    @return _fee The pool manager's fee
   */
  function FEE() external view returns (uint24 _fee);

  /**
    @notice Returns the non-WETH token of the underlying pool
    @return _token The non-WETH token of the underlying pool
   */
  function TOKEN() external view returns (IERC20 _token);

  /**
    @notice Returns the underlying UniswapV3 pool contract
    @return _pool The underlying UniswapV3 pool contract
   */
  function POOL() external view returns (IUniswapV3Pool _pool);

  /**
    @notice Returns true if WETH token is the token0
    @return _isWethToken0 If WETH is token0
   */
  function IS_WETH_TOKEN0() external view returns (bool _isWethToken0);

  /**
    @notice  Returns the pending to the corresponding account
    @param   _account The address of the account
    @return  wethPaid The amount of claimed rewards in WETH
    @return  tokenPaid The amount of claimed rewards in the non-WETH token
    @return  wethAvailable The amount of pending rewards in WETH
    @return  tokenAvailable The amount of pending rewards in the non-WETH token
   */
  // solhint-disable wonderland/non-state-vars-leading-underscore
  function seederRewards(address _account)
    external
    view
    returns (
      uint256 wethPaid,
      uint256 tokenPaid,
      uint256 wethAvailable,
      uint256 tokenAvailable
    );

  /**
    @notice Returns the status of a corresponding pool manager
    @return wethPerSeededLiquidity The value of the reward per WETH locked
    @return tokenPerSeededLiquidity The value of the reward per non-WETH token locked
   */
  // solhint-disable wonderland/non-state-vars-leading-underscore
  function poolRewards() external view returns (uint256 wethPerSeededLiquidity, uint256 tokenPerSeededLiquidity);

  /*///////////////////////////////////////////////////////////////
                            LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Deprecates the current lock manager and deploys a new one
   */
  function deprecateLockManager() external;

  /**
    @notice  Mint liquidity for the full-range position
    @param  _wethAmount The amount of WETH token to be inserted in the full-range position
    @param  _tokenAmount The amount of non-WETH token to be inserted in the full-range position
   */
  function mintLiquidityForFullRange(uint256 _wethAmount, uint256 _tokenAmount) external;

  /**
    @notice  Burns an amount of liquidity provided by a seeder
    @param  _liquidity The amount of liquidity
    @dev    The voting power for the user remains the same but they donate all rewards
   */
  function burn(uint256 _liquidity) external;

  /**
    @notice Callback that is called when calling the mint method in a UniswapV3 pool
    @dev    It is only called in the creation of the full range and when positions need to be updated
    @param  _amount0Owed  The amount of token0
    @param  _amount1Owed The amount of token1
    @param  _data The data that differentiates through an address whether to mint or transfer from for the full range
   */
  function uniswapV3MintCallback(
    uint256 _amount0Owed,
    uint256 _amount1Owed,
    bytes calldata _data
  ) external;

  /**
    @notice Increases the full-range position. The deposited tokens can not withdrawn
              and all of the generated fees with only benefit the pool itself
    @param  _donor The user that will provide WETH and the other token
    @param  _liquidity The liquidity that will be minted
    @param  _sqrtPriceX96 A sqrt price representing the current pool prices
   */
  function increaseFullRangePosition(
    address _donor,
    uint128 _liquidity,
    uint160 _sqrtPriceX96
  ) external;

  /**
    @notice Increases the full-range position with a given liquidity
    @dev    Pool manager will make a callback to the fee manager, who will provide the liquidity
    @param  _wethAmount The amount of WETH token to be inserted in the full-range position
    @param  _tokenAmount The amount of non-WETH to be inserted in the full-range position
    @return __amountWeth The amount in WETH added to the full range
    @return __amountToken The amount in non-WETH token added to the full range
   */
  function increaseFullRangePosition(uint256 _wethAmount, uint256 _tokenAmount) external returns (uint256 __amountWeth, uint256 __amountToken);

  /**
    @notice Claims the fees from the UniswapV3 pool and stores them in the FeeManager
   */
  function collectFees() external;

  /**
    @notice Returns the rewards generated by a caller
    @param  _to The recipient the rewards
    @return _rewardWeth The amount of rewards in WETH that were claimed
    @return _rewardToken The amount of rewards in non-WETH token that were claimed
   */
  function claimRewards(address _to) external returns (uint256 _rewardWeth, uint256 _rewardToken);

  /**
    @notice Returns the total amount of WETH claimable for a given account
    @param  _account The address of the account
    @return _wethClaimable The amount of WETH claimable
    @return _tokenClaimable The amount of non-WETH token claimable
   */
  function claimable(address _account) external view returns (uint256 _wethClaimable, uint256 _tokenClaimable);

  /**
    @notice Burns a little bit of liquidity in the pool to produce a new observation
    @dev    The oracle corrections require at least 2 post-manipulation observations to work properly
            When there is no new observations after a manipulation, the oracle will make then with this function
   */
  function burn1() external;
}
