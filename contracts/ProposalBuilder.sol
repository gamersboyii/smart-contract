// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {DAOTreasuryExecutionEngine} from "./DAOTreasuryExecutionEngine.sol";

/// @title ProposalBuilder
/// @notice Pure helpers that build single-call governance payloads targeting the treasury.
/// @dev Internal pure library: inlined into the caller, no deployment, no storage, no
///      trust assumptions — every payload still passes the full proposal + timelock path.
///      For ERC20 payouts, pass `data = abi.encodeCall(IERC20.transfer, (payee, amount))`
///      with `value = 0` and `tier = 0`; for plain ETH use `data = ""`.
library ProposalBuilder {
    /// @notice Schedule a treasury package: the common payment/configuration primitive.
    function treasuryPackage(
        address treasury,
        address payee,
        uint256 value,
        bytes memory data,
        uint8 tier,
        uint48 expiresAt,
        bytes32 predecessor
    ) internal pure returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) {
        bytes memory call = abi.encodeCall(
            DAOTreasuryExecutionEngine.approvePackage, (payee, value, data, tier, expiresAt, predecessor)
        );
        (targets, values, calldatas) = _single(treasury, 0, call);
    }

    /// @notice Reconfigure an execution tier (delay cap of 365 days still enforced).
    function configureTier(address treasury, uint8 tier, uint48 delay, uint256 maxNativeValue, bool enabled)
        internal
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
    {
        bytes memory call =
            abi.encodeCall(DAOTreasuryExecutionEngine.configureTier, (tier, delay, maxNativeValue, enabled));
        (targets, values, calldatas) = _single(treasury, 0, call);
    }

    /// @notice Add or remove a destination-allowlist entry.
    function setTargetAllowed(address treasury, address target, bool allowed)
        internal
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
    {
        bytes memory call = abi.encodeCall(DAOTreasuryExecutionEngine.setTargetAllowed, (target, allowed));
        (targets, values, calldatas) = _single(treasury, 0, call);
    }

    /// @notice Toggle the destination allowlist.
    function setTargetAllowlistEnabled(address treasury, bool enabled)
        internal
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
    {
        bytes memory call = abi.encodeCall(DAOTreasuryExecutionEngine.setTargetAllowlistEnabled, (enabled));
        (targets, values, calldatas) = _single(treasury, 0, call);
    }

    /// @notice Set the native reserve floor (zero disables).
    function setNativeReserveFloor(address treasury, uint256 floor)
        internal
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
    {
        bytes memory call = abi.encodeCall(DAOTreasuryExecutionEngine.setNativeReserveFloor, (floor));
        (targets, values, calldatas) = _single(treasury, 0, call);
    }

    /// @notice Proposal description hash for queue/execute/cancel calls.
    function descriptionHash(string memory description) internal pure returns (bytes32) {
        return keccak256(bytes(description));
    }

    function _single(address target, uint256 value, bytes memory call)
        private
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
    {
        targets = new address[](1);
        values = new uint256[](1);
        calldatas = new bytes[](1);
        (targets[0], values[0], calldatas[0]) = (target, value, call);
    }
}
