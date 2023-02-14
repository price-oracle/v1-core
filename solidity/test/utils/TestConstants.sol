// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import 'uni-v3-core/interfaces/IUniswapV3Factory.sol';

contract TestConstants {
  IUniswapV3Factory constant UNISWAP_V3_FACTORY = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
  address constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  bytes32 constant POOL_BYTECODE_HASH = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;
  int24 internal constant MIN_TICK = -887272;
  int24 internal constant MAX_TICK = 887272;
  uint160 internal constant MIN_SQRT_RATIO = 4295128739;
  uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;
  uint16 internal constant STARTING_CARDINALITY = 64;
  uint256 internal constant BLOCK_TIME = 12 seconds;
}
