// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.4 <0.9.0;

import 'solidity-utils/contracts/Roles.sol';

import '@interfaces/periphery/IGovernorMiniBravo.sol';

abstract contract GovernorMiniBravo is IGovernorMiniBravo, Roles {
  /**
    @notice The number of votes in support of a proposal required for a quorum to be reached and for a vote to succeed
   */
  uint256 public constant QUORUM = 70; // 70% of total votes

  /**
    @notice All proposals for each method. method number -> all proposals
   */
  mapping(uint256 => Proposal[]) internal _proposals;

  /**
    @notice Method number -> proposalId -> voter address -> votes
   */
  mapping(uint256 => mapping(uint256 => mapping(address => uint256))) internal _userVotes;

  /// @inheritdoc IGovernorMiniBravo
  function queue(uint256 _method, bytes memory _parameters) public {
    Proposal storage _proposal = _getLatest(_method);
    if (_proposal.timelockExpiry != 0) revert ProposalAlreadyQueued(_method, _proposal.id);
    if (!_quorumReached(_proposal.open, _proposal.forVotes)) revert QuorumNotReached(_method, _proposal.id);
    if (keccak256(_proposal.params) != keccak256(_parameters)) revert ParametersMismatch(_method, _proposal.params, _parameters);
    _proposal.timelockExpiry = block.timestamp + executionTimelock();
    emit ProposalQueued(_proposal.id, _method, _parameters);
  }

  /// @inheritdoc IGovernorMiniBravo
  function cancelVote(uint256 _method) public {
    Proposal storage _proposal = _getLatest(_method);
    uint256 _userCurrentVotes = _userVotes[_method][_proposal.id][msg.sender];
    if (_userCurrentVotes == 0) revert NoVotes();
    _proposal.forVotes = _proposal.forVotes - _userCurrentVotes;
    _userVotes[_method][_proposal.id][msg.sender] = 0;
    emit VoteCancelled(msg.sender, _method, _proposal.id);
  }

  /// @inheritdoc IGovernorMiniBravo
  function quorumReached(uint256 _method) external view returns (bool) {
    Proposal storage _proposal = _getLatest(_method);
    return _quorumReached(_proposal.open, _proposal.forVotes);
  }

  /// @inheritdoc IGovernorMiniBravo
  function isExecutable(uint256 _method) external view returns (bool _proposalIsExecutable) {
    Proposal storage _proposal = _getLatest(_method);
    _proposalIsExecutable = _isExecutable(_proposal.open, _proposal.timelockExpiry);
  }

  /// @inheritdoc IGovernorMiniBravo
  function execute(uint256 _method, bytes memory _parameters) public {
    Proposal storage _proposal = _getLatest(_method);
    if (!_isExecutable(_proposal.open, _proposal.timelockExpiry)) revert ProposalNotExecutable(_method, _proposal.id);
    if (keccak256(_proposal.params) != keccak256(_parameters)) revert ParametersMismatch(_method, _proposal.params, _parameters);
    _execute(_method, _parameters);
    _proposal.open = false;
    emit ProposalExecuted(_proposal.id, _method, _parameters);
  }

  /// @inheritdoc IGovernorMiniBravo
  function getLatest(uint256 _method) external view returns (Proposal memory _proposal) {
    _proposal = _getLatest(_method);
  }

  /// @inheritdoc IGovernorMiniBravo
  function cancelProposal(uint256 _method) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _cancelProposal(_method);
  }

  /**
    @notice Cancels the current proposal for a particular method
    @param  _method The method proposal to be canceled
   */
  function _cancelProposal(uint256 _method) internal {
    Proposal storage _proposal = _getLatest(_method);
    if (!_proposal.open) {
      revert ProposalClosed(_method, _proposal.id);
    }
    _proposal.open = false;
    emit ProposalCancelled(_proposal.id, _method, _proposal.params);
  }

  /**
    @notice Returns true if proposal reached quorum
    @param  _open True if the proposal is open
    @param  _forVotes The proposal votes amount
    @return _quorumAchieved True if the proposal is executable
   */
  function _quorumReached(bool _open, uint256 _forVotes) internal view returns (bool _quorumAchieved) {
    if (_open) {
      uint256 _quorum = (totalVotes() * QUORUM) / 100;
      _quorumAchieved = _forVotes >= _quorum;
    }
  }

  /**
    @notice Returns true if a proposal is executable
    @dev    A proposal is executable when it's open and passed the time lock
    @param  _open True if the proposal is open
    @param  _timelockExpiry The time lock expiry time of the proposal
    @return _proposalIsExecutable True if the proposal is executable
   */
  function _isExecutable(bool _open, uint256 _timelockExpiry) internal view returns (bool _proposalIsExecutable) {
    _proposalIsExecutable = _open && _timelockExpiry > 0 && _timelockExpiry <= block.timestamp;
  }

  /**
    @notice Returns the latest proposal created for a method
    @param  _method The method proposal to return
    @return _proposal The latest proposal for the method
   */
  function _getLatest(uint256 _method) internal view returns (Proposal storage _proposal) {
    Proposal[] storage _methodProposals = _proposals[_method];
    _proposal = _methodProposals[_methodProposals.length - 1];
  }

  /**
    @notice Executes a particular proposal
    @param _method The method to be called
    @param _parameters The parameters to be sent to the call
   */
  function _execute(uint256 _method, bytes memory _parameters) internal virtual;

  /**
    @notice Creates a proposal
    @param  _method The method to create a proposal for
    @param  _parameters The parameters for the proposal
   */
  function _propose(uint256 _method, bytes memory _parameters) internal {
    Proposal[] storage _allMethodProposals = _proposals[_method];
    uint256 _latestId = _allMethodProposals.length > 0 ? _allMethodProposals[_allMethodProposals.length - 1].id : 0;
    Proposal memory _newProposal = Proposal({id: _latestId + 1, params: _parameters, forVotes: 0, open: true, timelockExpiry: 0});
    _allMethodProposals.push(_newProposal);
    emit NewProposal(_newProposal.id, _method, _newProposal.params);
  }

  /**
    @notice Votes yes on a proposal
    @param  _method The method of the proposal to vote on
    @param  _params The parameters for the proposal
    @param  _voter The voter that accepts the proposal
   */
  function _acceptProposal(
    uint256 _method,
    bytes memory _params,
    address _voter
  ) internal {
    Proposal storage _proposal = _getLatest(_method);
    if (keccak256(_proposal.params) != keccak256(_params)) revert ParametersMismatch(_method, _proposal.params, _params);
    if (_userVotes[_method][_proposal.id][_voter] > 0) revert AlreadyVoted(_method, _proposal.id);
    uint256 _votes = votingPower(_voter);
    _userVotes[_method][_proposal.id][_voter] = _votes;
    _proposal.forVotes = _proposal.forVotes + _votes;
    emit NewVote(_voter, _votes, _method, _proposal.id);
  }

  /// @inheritdoc IGovernorMiniBravo
  function votingPower(address _user) public view virtual returns (uint256 _balance);

  /// @inheritdoc IGovernorMiniBravo
  function totalVotes() public view virtual returns (uint256 _totalVotes);

  /// @inheritdoc IGovernorMiniBravo
  function executionTimelock() public pure returns (uint256 _executionTimelock) {
    _executionTimelock = 1 weeks;
  }
}
