// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import 'isolmate/tokens/ERC20.sol';

contract BasicToken is ERC20 {
  constructor() ERC20('Basic', 'BASIC', 18) {}
}
