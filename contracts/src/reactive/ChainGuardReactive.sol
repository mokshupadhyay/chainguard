// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {ISystemContract} from "@reactive/src/interfaces/ISystemContract.sol";
import {IReactive} from "@reactive/src/interfaces/IReactive.sol";
import {AbstractReactive} from "@reactive/src/base/AbstractReactive.sol";

/// @title ChainGuardReactive
/// @notice Lives on Reactive Lasna. Holds a mirror of every *registered* Guard's policy and decides,
/// inside `react()`, whether an observed ERC-20 `Approval` must be revoked. If so it requests a
/// callback to `GuardModule.revoke` on the origin chain.
///
/// Subscription model (no wildcard emitters, so arbitrary contracts cannot make us pay for `react()`):
///  1. `setFactory` (admin, once)  -> subscribe to the trusted factory's `GuardCreated` only.
///  2. On `GuardCreated`, `react()` registers the Guard and subscribes, at runtime, to
///       - that Guard's own `ChainGuardPolicySet` (contract = guard), and
///       - `Approval` on each allowlisted token filtered to owner = that Guard (topic1 = guard).
///  3. Everything else is ignored, and re-checked inside `react()` as defense in depth.
contract ChainGuardReactive is AbstractReactive {
    // keccak256 of the event signatures (computed, not hand-copied)
    uint256 public constant APPROVAL_TOPIC =
        uint256(keccak256("Approval(address,address,uint256)"));
    uint256 public constant POLICY_TOPIC =
        uint256(keccak256("ChainGuardPolicySet(address,bool,bool,uint256)"));
    uint256 public constant GUARD_CREATED_TOPIC =
        uint256(keccak256("GuardCreated(address,address,bool,bool,uint256)"));
    uint256 public constant SPENDER_MODE_TOPIC = uint256(keccak256("SpenderModeSet(bool)"));
    uint256 public constant SPENDER_RULE_TOPIC = uint256(keccak256("SpenderRuleSet(address,bool)"));
    uint256 public constant MAX_TOKENS = 8;

    uint256 public immutable ORIGIN_CHAIN_ID;
    address public immutable admin;
    /// @notice Upper bound on registered Guards; bounds how much runtime subscription work can be forced on us.
    uint256 public immutable maxGuards;
    uint64 public callbackGasLimit = 400_000;

    struct Policy {
        bool enabled;
        bool revokeUnlimited;
        uint256 maxAllowance;
    }

    address public factory; // trusted GuardFactory, set once
    address[] private _tokens; // fixed at construction (bounded), watched for every registered Guard
    mapping(address => bool) public isWatchedToken;
    mapping(address => bool) public registered; // Guards created by the trusted factory
    uint256 public guardCount;
    mapping(address => Policy) public policies; // keyed by registered Guard
    mapping(address => bool) public restrictSpenders; // Guard => only allowlisted spenders may hold approvals
    mapping(address => mapping(address => bool)) public spenderAllowed; // Guard => spender => allowed

    event FactorySet(address indexed factory);
    event GuardRegistered(
        address indexed owner,
        address indexed guard,
        bool enabled,
        bool revokeUnlimited,
        uint256 maxAllowance
    );
    event GuardRejected(address indexed guard, string reason);
    event PolicyMirrored(
        address indexed guard, bool enabled, bool revokeUnlimited, uint256 maxAllowance
    );
    event SpenderModeMirrored(address indexed guard, bool restrictToAllowlist);
    event SpenderRuleMirrored(address indexed guard, address indexed spender, bool allowed);
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

    error NotAdmin();
    error FactoryAlreadySet();
    error BadConfig();

    constructor(uint256 originChainId_, address[] memory tokens_, uint256 maxGuards_) payable {
        if (tokens_.length == 0 || tokens_.length > MAX_TOKENS || maxGuards_ == 0) {
            revert BadConfig();
        }
        ORIGIN_CHAIN_ID = originChainId_;
        admin = msg.sender;
        maxGuards = maxGuards_;
        for (uint256 i; i < tokens_.length; i++) {
            _tokens.push(tokens_[i]);
            isWatchedToken[tokens_[i]] = true;
        }
    }

    function tokens() external view returns (address[] memory) {
        return _tokens;
    }

    /// @notice One-time: trust this factory. Must be called after the factory is deployed and before any Guard is created.
    function setFactory(address factory_) external {
        if (msg.sender != admin) revert NotAdmin();
        if (factory != address(0)) revert FactoryAlreadySet();
        if (factory_ == address(0)) revert BadConfig();
        factory = factory_;
        SYSTEM.subscribe(
            ORIGIN_CHAIN_ID,
            factory_,
            GUARD_CREATED_TOPIC,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        emit FactorySet(factory_);
    }

    function setCallbackGasLimit(uint64 gasLimit_) external {
        if (msg.sender != admin) revert NotAdmin();
        callbackGasLimit = gasLimit_;
    }

    function coverDebt() external {
        _coverDebt();
    }

    /// @notice Policy evaluation happens here, on Reactive Lasna.
    /// @inheritdoc IReactive
    function react(LogRecord calldata log_) external override onlySystem {
        if (log_.chainId != ORIGIN_CHAIN_ID) return;
        if (log_.topic0 == GUARD_CREATED_TOPIC) return _onGuardCreated(log_);
        if (log_.topic0 == POLICY_TOPIC) return _onPolicy(log_);
        if (log_.topic0 == SPENDER_MODE_TOPIC) return _onSpenderMode(log_);
        if (log_.topic0 == SPENDER_RULE_TOPIC) return _onSpenderRule(log_);
        // ERC-20 Approval has 3 topics (LOG3); ERC-721 Approval has 4, so this filters NFTs out.
        if (log_.topic0 == APPROVAL_TOPIC && log_.opCode == 3) return _onApproval(log_);
    }

    function _onGuardCreated(LogRecord calldata log_) internal {
        // Only the trusted factory's event registers a Guard (the subscription already filters by emitter).
        if (factory == address(0) || log_.contractAddress != factory) return;
        address guard = address(uint160(log_.topic2));
        if (registered[guard]) return; // idempotent on replay
        if (guardCount >= maxGuards) {
            emit GuardRejected(guard, "max-guards");
            return;
        }
        (bool enabled, bool revokeUnlimited, uint256 cap) =
            abi.decode(log_.data, (bool, bool, uint256));
        registered[guard] = true;
        guardCount++;
        policies[guard] = Policy(enabled, revokeUnlimited, cap);

        // Runtime subscriptions, scoped to this Guard only.
        SYSTEM.subscribe(
            ORIGIN_CHAIN_ID, guard, POLICY_TOPIC, REACTIVE_IGNORE, REACTIVE_IGNORE, REACTIVE_IGNORE
        );
        SYSTEM.subscribe(
            ORIGIN_CHAIN_ID,
            guard,
            SPENDER_MODE_TOPIC,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        SYSTEM.subscribe(
            ORIGIN_CHAIN_ID,
            guard,
            SPENDER_RULE_TOPIC,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        for (uint256 i; i < _tokens.length; i++) {
            SYSTEM.subscribe(
                ORIGIN_CHAIN_ID,
                _tokens[i],
                APPROVAL_TOPIC,
                uint256(uint160(guard)),
                REACTIVE_IGNORE,
                REACTIVE_IGNORE
            );
        }
        // Readiness handshake: tell the Guard (on the origin chain) it is registered. The Guard blocks
        // approvals/policy changes until this callback lands, so users never act before protection exists.
        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: log_.chainId,
                recipient: guard,
                gasLimit: callbackGasLimit,
                payload: abi.encodeWithSignature(
                    "confirmRegistered(address,address[])", address(0), _tokens
                )
            })
        );
        emit GuardRegistered(address(uint160(log_.topic1)), guard, enabled, revokeUnlimited, cap);
    }

    function _onPolicy(LogRecord calldata log_) internal {
        // Only a registered Guard may set its own policy; any other emitter is ignored.
        if (!registered[log_.contractAddress]) return;
        (bool enabled, bool revokeUnlimited, uint256 cap) =
            abi.decode(log_.data, (bool, bool, uint256));
        policies[log_.contractAddress] = Policy(enabled, revokeUnlimited, cap);
        emit PolicyMirrored(log_.contractAddress, enabled, revokeUnlimited, cap);
    }

    function _onSpenderMode(LogRecord calldata log_) internal {
        if (!registered[log_.contractAddress]) return;
        restrictSpenders[log_.contractAddress] = abi.decode(log_.data, (bool));
        emit SpenderModeMirrored(log_.contractAddress, restrictSpenders[log_.contractAddress]);
    }

    function _onSpenderRule(LogRecord calldata log_) internal {
        if (!registered[log_.contractAddress]) return;
        address spender = address(uint160(log_.topic1));
        bool allowed = abi.decode(log_.data, (bool));
        spenderAllowed[log_.contractAddress][spender] = allowed;
        emit SpenderRuleMirrored(log_.contractAddress, spender, allowed);
        // Un-trusting a spender must also clear what it already holds, not only its next approval.
        if (
            !allowed && restrictSpenders[log_.contractAddress]
                && policies[log_.contractAddress].enabled
        ) {
            for (uint256 i; i < _tokens.length; i++) {
                SYSTEM.requestCallbackV_1_0(
                    ISystemContract.CallbackConfiguration_V_1_0({
                        chainId: log_.chainId,
                        recipient: log_.contractAddress,
                        gasLimit: callbackGasLimit,
                        payload: abi.encodeWithSignature(
                            "revoke(address,address,address)", address(0), _tokens[i], spender
                        )
                    })
                );
                emit RevokeRequested(
                    log_.contractAddress, _tokens[i], spender, 0, "spender-removed"
                );
            }
        }
    }

    function _onApproval(LogRecord calldata log_) internal {
        address guard = address(uint160(log_.topic1));
        // Registered Guard + allowlisted token only (the subscription also enforces both).
        if (!registered[guard] || !isWatchedToken[log_.contractAddress]) return;
        address spender = address(uint160(log_.topic2));
        uint256 value = abi.decode(log_.data, (uint256));

        (bool revoke, string memory reason) = _evaluate(guard, spender, value);
        if (!revoke) {
            emit ApprovalIgnored(guard, log_.contractAddress, spender, value);
            return;
        }
        // First payload argument is a placeholder; the network overwrites it with this contract's address.
        bytes memory payload = abi.encodeWithSignature(
            "revokeIfUnchanged(address,address,address,uint256)",
            address(0),
            log_.contractAddress,
            spender,
            value
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

    function _evaluate(address guard, address spender, uint256 value)
        internal
        view
        returns (bool, string memory)
    {
        Policy memory p = policies[guard];
        if (!p.enabled) return (false, "");
        if (value == 0) return (false, ""); // a revocation itself must never re-trigger a revoke
        if (restrictSpenders[guard] && !spenderAllowed[guard][spender]) {
            return (true, "spender-not-allowed");
        }
        if (p.revokeUnlimited && value == type(uint256).max) return (true, "unlimited");
        if (p.maxAllowance > 0 && value > p.maxAllowance) return (true, "over-cap");
        return (false, "");
    }
}
