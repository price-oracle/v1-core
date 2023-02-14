// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import 'solidity-utils/test/DSTestPlus.sol';
import '@test/utils/ContractDeploymentAddress.sol';

contract Target {
  uint256 private _a;

  function get() external view returns (uint256) {
    return _a;
  }

  function set(uint256 __a) external {
    _a = __a;
  }
}

contract UnitContractDeploymentAddressAddressFrom is DSTestPlus {
  Target target;
  address deployer = label(address(100), 'deployer');

  function testDeploy(uint8 nonce) external {
    vm.assume(nonce < type(uint8).max); // avoid overflow on nonce + 1

    Target _target;
    for (uint256 i; i < nonce; i++) _target = new Target();

    address nextDeployment = ContractDeploymentAddress.addressFrom(address(this), nonce + 1);
    _target = new Target();

    assertEq(nextDeployment, address(_target));
  }

  function testNewAddress() external {
    assertTrue(newAddress() != newAddress());
  }
}
