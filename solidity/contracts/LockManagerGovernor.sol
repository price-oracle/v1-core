// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.4 <0.9.0;

import '@interfaces/ILockManagerGovernor.sol';
import '@contracts/periphery/GovernorMiniBravo.sol';

abstract contract LockManagerGovernor is ILockManagerGovernor, GovernorMiniBravo {
  /// @inheritdoc ILockManagerGovernor
  IPoolManagerFactory public immutable POOL_MANAGER_FACTORY;
  /// @inheritdoc ILockManagerGovernor
  bool public deprecated;

  modifier notDeprecated() {
    if (deprecated) revert LockManager_Deprecated();
    _;
  }

  constructor(IPoolManager.LockManagerParams memory _lockManagerParams) payable GovernorMiniBravo() {
    _grantRole(DEFAULT_ADMIN_ROLE, _lockManagerParams.governance);
    POOL_MANAGER_FACTORY = _lockManagerParams.factory;
    _propose(uint256(Methods.Deprecate), abi.encode());
  }

  /// @inheritdoc ILockManagerGovernor
  function acceptDeprecate() external {
    _acceptProposal(uint256(Methods.Deprecate), abi.encode(), msg.sender);
  }

  /**
    @notice Cancels votes amount for all proposals voted by the voter
    @param  _voter The voter to remove the votes from
    @param  _votes The number of votes to remove
   */
  function _cancelVotes(address _voter, uint256 _votes) internal virtual {
    _transferVotes(_voter, address(0), _votes);
  }

  /**
    @notice Executes a proposal
    @param  _method The method to be called
   */
  function _execute(uint256 _method, bytes memory) internal override {
    Methods _lockManagerMethod = Methods(_method);
    if (_lockManagerMethod == Methods.Deprecate) {
      _deprecate();
    }
  }

  /**
    @notice Deprecates the lockManager
   */
  function _deprecate() internal virtual {
    deprecated = true;
  }

  /**
    @notice Transfers votes from one user to another
    @param  _sender The votes sender
    @param  _receiver The votes receiver
    @param  _votes The number of votes to be transferred
   */
  function _transferVotes(
    address _sender,
    address _receiver,
    uint256 _votes
  ) internal {
    for (uint256 _i; _i < uint256(Methods.LatestMethod); ++_i) {
      if (_proposals[_i].length > 0) {
        Proposal storage _proposal = _getLatest(_i);
        if (_proposal.open) {
          uint256 _senderVotes = _userVotes[_i][_proposal.id][_sender];
          uint256 _receiverVotes = (_receiver == address(0)) ? 0 : _userVotes[_i][_proposal.id][_receiver];

          if (_senderVotes > 0) {
            if (_senderVotes < _votes) revert LockManager_ArithmeticUnderflow();
            // Subtract votes from the sender
            _userVotes[_i][_proposal.id][_sender] = _senderVotes - _votes;
            // if the receiver has no votes, subtract from the proposal
            if (_receiverVotes == 0) _proposal.forVotes = _proposal.forVotes - _votes;
          }

          // Checks if the receiver voted yes
          if (_receiverVotes > 0) {
            // If yes, then: add votes to the receiver
            _userVotes[_i][_proposal.id][_receiver] = _receiverVotes + _votes;
            // if the sender has no votes, add to the proposal
            if (_senderVotes == 0) _proposal.forVotes = _proposal.forVotes + _votes;
          }
        }
      }
    }
  }
}
