// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.4 <0.9.0;

interface IGovernorMiniBravo {
  /*///////////////////////////////////////////////////////////////
                              ERRORS
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Thrown when trying to queue a proposal that was already queued
   */
  error ProposalAlreadyQueued(uint256 _method, uint256 _id);

  /**
    @notice Thrown when trying to queue a proposal that has not reached quorum
   */
  error QuorumNotReached(uint256 _method, uint256 _id);

  /**
    @notice Thrown when trying to execute a proposal that is canceled or not on quorum
   */
  error ProposalNotExecutable(uint256 _method, uint256 _id);

  /**
    @notice Thrown when parameters inputted do not match the saved parameters
   */
  error ParametersMismatch(uint256 _method, bytes _expectedParameters, bytes _actualParameters);

  /**
    @notice Thrown when the proposal is in a closed state
   */
  error ProposalClosed(uint256 _method, uint256 _id);

  /**
    @notice Thrown when the voter already voted
   */
  error AlreadyVoted(uint256 _method, uint256 _id);

  /**
    @notice Thrown when a user tries to cancel their vote with 0 votes
   */
  error NoVotes();

  /*///////////////////////////////////////////////////////////////
                              EVENTS
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Emitted when a new proposal is created
   */
  event NewProposal(uint256 _id, uint256 _method, bytes _params);

  /**
    @notice Emitted when a user votes on a proposal
   */
  event NewVote(address _voter, uint256 _votes, uint256 _method, uint256 _id);

  /**
    @notice Emitted when a proposal is canceled
   */
  event ProposalCancelled(uint256 _id, uint256 _method, bytes _params);

  /**
    @notice Emitted when a new proposal is executed
   */
  event ProposalExecuted(uint256 _id, uint256 _method, bytes _params);

  /**
    @notice Emitted when a voter cancels their vote
   */
  event VoteCancelled(address _voter, uint256 _method, uint256 _id);

  /**
    @notice Emitted when a proposal is queued
   */
  event ProposalQueued(uint256 _id, uint256 _method, bytes _params);

  /*///////////////////////////////////////////////////////////////
                              STRUCTS
  //////////////////////////////////////////////////////////////*/
  /**
    @notice A proposal for a particular method call
   */
  struct Proposal {
    uint256 id;
    bytes params;
    uint256 forVotes;
    bool open;
    uint256 timelockExpiry;
  }

  /*///////////////////////////////////////////////////////////////
                            VARIABLES
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Returns the needed quorum for a proposal to pass
    @return _quorum The needed quorum percentage
   */
  function QUORUM() external view returns (uint256 _quorum);

  /**
    @notice Returns the voting power of a particular user
    @param  _user The user whose voting power will be returned
    @return _balance The voting power of the user
   */
  function votingPower(address _user) external view returns (uint256 _balance);

  /**
    @notice Returns the total available votes
    @return _totalVotes The total available votes
   */
  function totalVotes() external view returns (uint256 _totalVotes);

  /**
    @notice Returns true if the latest proposal for the target method is executable
    @param  _method The method of the proposal
    @return _availableToExecute True if the proposal is executable
   */
  function isExecutable(uint256 _method) external view returns (bool _availableToExecute);

  /**
    @notice Returns the tome lock to execute transactions
    @return _executionTimelock The time lock to execute transactions
   */
  function executionTimelock() external view returns (uint256 _executionTimelock);

  /*///////////////////////////////////////////////////////////////
                              LOGIC
  //////////////////////////////////////////////////////////////*/

  /**
    @notice Cancels a vote by a user on a particular method
    @param  _method The method to subtract the votes
   */
  function cancelVote(uint256 _method) external;

  /**
    @notice Executes a particular proposal if it reaches quorum
    @param  _method The target method
    @param  _parameters The proposal parameters
   */
  function execute(uint256 _method, bytes memory _parameters) external;

  /**
    @notice Returns the latest proposal created for a method
    @param  _method The target method proposal
    @return _proposal The latest proposal for the method
   */
  function getLatest(uint256 _method) external view returns (Proposal memory _proposal);

  /**
    @notice Cancels a proposal
    @dev    Admin can only call
    @param  _method The method proposal to cancel
   */
  function cancelProposal(uint256 _method) external;

  /**
    @notice Queue a particular proposal if it reaches the required quorum
    @param  _method The method to be called when executed
    @param  _parameters The parameters for the proposal
   */
  function queue(uint256 _method, bytes memory _parameters) external;

  /**
    @notice Returns true if proposal reached the required quorum
    @param  _method The method to be called when executed
    @return _quorumReached True if the proposal is executable
   */
  function quorumReached(uint256 _method) external view returns (bool _quorumReached);
}
