// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import '@test/e2e/Common.sol';
import '@contracts/jobs/CardinalityJob.sol';
import 'isolmate/utils/SafeTransferLib.sol';

import {HighDecimalToken} from 'weird-erc20/HighDecimals.sol';
import {LowDecimalToken} from 'weird-erc20/LowDecimals.sol';
import {MissingReturnToken} from 'weird-erc20/MissingReturns.sol';
import {NoRevertToken} from 'weird-erc20/NoRevert.sol';
import {Uint96ERC20} from 'weird-erc20/Uint96.sol';
import {TransferFeeToken} from 'weird-erc20/TransferFee.sol';

contract E2EWeirdERC20 is CommonE2EBase {
  using SafeTransferLib for IERC20;

  IPoolManager poolManagerWeirdToken;
  IERC20 _token;
  uint256 _totalSupply = 100000000000000000 ether;
  uint256 _numberOfSwaps = 10;

  function testHighDecimals() public {
    _token = IERC20(address(new HighDecimalToken(_totalSupply)));
    uint256 _delta = 100 * (10**(_token.decimals() - 18));
    _createAndTestPool(_token, _delta);
    _tradeAndCollectFees(_token, poolManagerWeirdToken, _delta);
  }

  function testLowDecimals() public {
    _token = IERC20(address(new LowDecimalToken(_totalSupply)));
    _createAndTestPool(_token, DELTA);
    _tradeAndCollectFees(_token, poolManagerWeirdToken, DELTA);
  }

  function testMissingReturns() public {
    _token = IERC20(address(new MissingReturnToken(_totalSupply)));
    _createAndTestPool(_token, DELTA);
    _tradeAndCollectFees(_token, poolManagerWeirdToken, DELTA);
  }

  function testNoRevertPasses() public {
    _token = IERC20(address(new NoRevertToken(_totalSupply)));
    _createAndTestPool(_token, DELTA);
    _tradeAndCollectFees(_token, poolManagerWeirdToken, DELTA);
  }

  function testNoRevertShouldRevertWhenNotEnoughAllowance() public {
    _token = IERC20(address(new NoRevertToken(_totalSupply)));
    _createAndTestPool(_token, DELTA);
    (uint160 _sqrtPriceX96, , , , , , ) = poolManagerWeirdToken.POOL().slot0();

    // To avoid OLD error from Uniswap
    vm.warp(block.timestamp + priceOracle.MIN_CORRECTION_PERIOD() * 2);

    vm.startPrank(user1);
    _token.approve(address(poolManagerWeirdToken), 0);
    vm.expectRevert(bytes('TRANSFER_FROM_FAILED'));
    poolManagerWeirdToken.increaseFullRangePosition(user1, 1 ether, _sqrtPriceX96);
    vm.stopPrank();
  }

  function testUint96() public {
    _token = IERC20(address(new Uint96ERC20(uint96(_totalSupply))));
    _createAndTestPool(_token, DELTA);
    _tradeAndCollectFees(_token, poolManagerWeirdToken, DELTA);
  }

  // TODO: Project does not support fee on transfer tokens for now
  // function testTransferFee() public {
  //   vm.startPrank(user1);
  //   uint256 _fee = 1000; // 1000 wei transfer fee fixed
  //   TransferFeeToken _token = new TransferFeeToken(_totalSupply, _fee);
  //   _token = IERC20(address(_token));
  //   _createAndTestPool(_token, DELTA);
  //   _tradeAndCollectFees(_token, poolManagerWeirdToken, DELTA);
  //   vm.stopPrank();
  // }

  function _createAndTestPool(IERC20 token, uint256 _delta) internal {
    deal(address(token), user1, _totalSupply);

    uint256 _balanceBefore = token.balanceOf(user1);

    vm.startPrank(user1);
    token.safeApprove(address(uniswapRouter), type(uint256).max);
    poolManagerWeirdToken = _createPoolManager(token);
    vm.stopPrank();

    uint256 _balanceAfter = token.balanceOf(user1);
    uint256 _poolBalanceAfter = token.balanceOf(address(poolManagerWeirdToken.POOL()));

    assertApproxEqAbs(_balanceBefore, _balanceAfter + liquidity, _delta);
    assertApproxEqAbs(_poolBalanceAfter, liquidity, _delta);
    assertApproxEqAbs(poolManagerWeirdToken.votingPower(user1), liquidity, _delta);
  }

  function _tradeAndCollectFees(
    IERC20 _weirdToken,
    IPoolManager _poolManager,
    uint256 _delta
  ) internal {
    // Avoid OLD error from Uniswap
    advanceTime(priceOracle.MIN_CORRECTION_PERIOD() * 2);

    // Make swaps to add fees
    vm.startPrank(user1);
    uint256 _swapSize = 3 * (10**_weirdToken.decimals());
    _performMultipleSwaps(_weirdToken, weth, _swapSize, _numberOfSwaps);

    uint256 _tokenFees = ((_numberOfSwaps / 2) * _swapSize * poolFee) / 1000000;
    uint256 _tokenFeesForFullRange = _tokenFees / 2;

    (uint160 _sqrtPriceX96, , , , , , ) = _poolManager.POOL().slot0();
    _poolManager.increaseFullRangePosition(user1, 1 ether, _sqrtPriceX96);
    vm.stopPrank();

    // Collect fees
    _poolManager.collectFees();

    // FeeManager should now have more fees
    IFeeManager _feeManager = _poolManager.feeManager();
    (, uint256 _tokenForFullRange) = _feeManager.poolManagerDeposits(_poolManager);
    assertApproxEqAbs(_tokenForFullRange, _tokenFeesForFullRange, _delta);
  }
}
