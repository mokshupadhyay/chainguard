// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {ISystemContract} from "@reactive/src/interfaces/ISystemContract.sol";
import {IReactive} from "@reactive/src/interfaces/IReactive.sol";
import {AbstractReactive} from "@reactive/src/base/AbstractReactive.sol";

/// @title ChainGuardReactive
/// @notice Lives on Reactive Lasna. Holds a mirror of every Guard's policy and decides, inside
/// `react()`, whether an observed ERC-20 `Approval` must be revoked. If so it requests a callback
/// to `GuardModule.revoke` on the origin chain.
contract ChainGuardReactive is AbstractReactive {
    // keccak256("Approval(address,address,uint256)")
    uint256 public constant APPROVAL_TOPIC =
        uint256(keccak256("Approval(address,address,uint256)"));
    // keccak256("ChainGuardPolicySet(address,bool,bool,uint256)")
    uint256 public constant POLICY_TOPIC =
        uint256(keccak256("ChainGuardPolicySet(address,bool,bool,uint256)"));

    uint256 public immutable ORIGIN_CHAIN_ID;
    address public immutable admin;
    uint64 public callbackGasLimit = 400_000;

    struct Policy {
        bool enabled;
        bool revokeUnlimited;
        uint256 maxAllowance;
    }

    /// @dev keyed by Guard address (the emitter of ChainGuardPolicySet). Anyone can emit that
    /// event, but it only ever configures the emitter's own address, so it cannot affect others.
    mapping(address => Policy) public policies;

    event PolicyMirrored(
        address indexed guard, bool enabled, bool revokeUnlimited, uint256 maxAllowance
    );
    event RevokeRequested(
        address indexed guard,
        address indexed token,
        address indexed spender,
        uint256 value,
        string reason
    );
    event ApprovalIgnored(
        address indexed guard, address indexed token, address indexed spender, uint256 value
    );
    event TokenWatched(address indexed token);

    error NotAdmin();

    constructor(uint256 originChainId_, address[] memory tokens_) payable {
        ORIGIN_CHAIN_ID = originChainId_;
        admin = msg.sender;
        // Guard policy updates from any contract on the origin chain.
        SYSTEM.subscribe(
            originChainId_,
            address(0),
            POLICY_TOPIC,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        for (uint256 i; i < tokens_.length; i++) {
            _watch(tokens_[i]);
        }
    }

    function watchToken(address token) external {
        if (msg.sender != admin) revert NotAdmin();
        _watch(token);
    }

    function setCallbackGasLimit(uint64 gasLimit_) external {
        if (msg.sender != admin) revert NotAdmin();
        callbackGasLimit = gasLimit_;
    }

    function coverDebt() external {
        _coverDebt();
    }

    function _watch(address token) internal {
        SYSTEM.subscribe(
            ORIGIN_CHAIN_ID,
            token,
            APPROVAL_TOPIC,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        emit TokenWatched(token);
    }

    /// @notice Policy evaluation happens here, on Reactive Lasna.
    /// @inheritdoc IReactive
    function react(LogRecord calldata log_) external override onlySystem {
        if (log_.chainId != ORIGIN_CHAIN_ID) return;

        if (log_.topic0 == POLICY_TOPIC) {
            (bool enabled, bool revokeUnlimited, uint256 maxAllowance) =
                abi.decode(log_.data, (bool, bool, uint256));
            policies[log_.contractAddress] = Policy(enabled, revokeUnlimited, maxAllowance);
            emit PolicyMirrored(log_.contractAddress, enabled, revokeUnlimited, maxAllowance);
            return;
        }

        // ERC-20 Approval has 3 topics (LOG3); ERC-721 Approval has 4, so this filters NFTs out.
        if (log_.topic0 != APPROVAL_TOPIC || log_.opCode != 3) return;

        address guard = address(uint160(log_.topic1));
        address spender = address(uint160(log_.topic2));
        uint256 value = abi.decode(log_.data, (uint256));

        (bool revoke, string memory reason) = _evaluate(policies[guard], value);
        if (!revoke) {
            emit ApprovalIgnored(guard, log_.contractAddress, spender, value);
            return;
        }

        // First payload argument is a placeholder; the network overwrites it with this contract's address.
        bytes memory payload = abi.encodeWithSignature(
            "revoke(address,address,address)", address(0), log_.contractAddress, spender
        );
        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: log_.chainId,
                recipient: guard,
                gasLimit: callbackGasLimit,
                payload: payload
            })
        );
        emit RevokeRequested(guard, log_.contractAddress, spender, value, reason);
    }

    function _evaluate(Policy memory p, uint256 value) internal pure returns (bool, string memory) {
        if (!p.enabled) return (false, "");
        if (p.revokeUnlimited && value == type(uint256).max) return (true, "unlimited");
        if (p.maxAllowance > 0 && value > p.maxAllowance) return (true, "over-cap");
        return (false, "");
    }
}
