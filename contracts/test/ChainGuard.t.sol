// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test, Vm} from "forge-std/Test.sol";
import {IReactive} from "@reactive/src/interfaces/IReactive.sol";
import {IPayable} from "@reactive/src/interfaces/IPayable.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {GuardModule} from "../src/GuardModule.sol";
import {GuardFactory} from "../src/GuardFactory.sol";
import {ChainGuardReactive} from "../src/reactive/ChainGuardReactive.sol";
import {MockSystem} from "./mocks/MockSystem.sol";

contract ChainGuardTest is Test {
    address constant SYSTEM = 0x8888888888888888888888888888888888888888;
    address constant PROXY = 0x476F44b11F5C942c58f4c8E3d0300E5710743585;
    uint256 constant ORIGIN = 84532;
    uint256 constant IGNORE = 0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad;

    MockERC20 token;
    GuardFactory factory;
    GuardModule guard;
    ChainGuardReactive rc;
    MockSystem sys = MockSystem(payable(SYSTEM));

    address user = makeAddr("user");
    address attacker = makeAddr("attacker");

    function setUp() public {
        vm.etch(SYSTEM, address(new MockSystem()).code);
        token = new MockERC20("Mock USDC", "mUSDC");
        address[] memory tokens = new address[](1);
        tokens[0] = address(token);
        rc = new ChainGuardReactive(ORIGIN, tokens, 3);
        factory = new GuardFactory(IPayable(payable(PROXY)), address(rc));
        rc.setFactory(address(factory));
        // Create a real Guard through the real factory and feed its real GuardCreated log to react().
        guard = GuardModule(payable(_createViaFactory(user)));
        _confirm(address(guard)); // deliver Lasna's registration confirmation, as the callback proxy would
        sys.resetCallbacks(); // so later tests count only revoke callbacks
        token.mint(address(guard), 1_000 ether);
    }

    /// @dev Delivers the most recent `confirmRegistered` callback request to `g` the way the proxy does
    /// (the network replaces the first argument with the reactive contract's address).
    function _confirm(address g) internal {
        (, address recipient,, bytes memory payload) = sys.lastCallback();
        assertEq(recipient, g);
        (, address[] memory toks) = abi.decode(_args(payload), (address, address[]));
        vm.prank(PROXY);
        GuardModule(payable(g)).confirmRegistered(address(rc), toks);
    }

    // ------------------------------------------------------------ helpers
    function _createViaFactory(address owner_) internal returns (address g) {
        vm.recordLogs();
        vm.prank(owner_);
        g = factory.createGuard();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter == address(factory) && logs[i].topics[0] == bytes32(rc.GUARD_CREATED_TOPIC())) {
                _react(_fromVmLog(logs[i]));
            }
        }
    }

    function _fromVmLog(Vm.Log memory l) internal pure returns (IReactive.LogRecord memory) {
        return IReactive.LogRecord(
            ORIGIN,
            l.emitter,
            uint256(l.topics[0]),
            l.topics.length > 1 ? uint256(l.topics[1]) : 0,
            l.topics.length > 2 ? uint256(l.topics[2]) : 0,
            0,
            l.data,
            1,
            l.topics.length,
            0,
            0xabc,
            0
        );
    }

    function _log(uint256 topic0, uint256 t1, uint256 t2, bytes memory data, address emitter, uint256 opCode)
        internal
        pure
        returns (IReactive.LogRecord memory)
    {
        return IReactive.LogRecord(ORIGIN, emitter, topic0, t1, t2, 0, data, 1, opCode, 0, 0xabc, 0);
    }

    function _approvalLog(address owner_, address spender, uint256 value, address tkn)
        internal
        view
        returns (IReactive.LogRecord memory)
    {
        return _log(rc.APPROVAL_TOPIC(), uint256(uint160(owner_)), uint256(uint160(spender)), abi.encode(value), tkn, 3);
    }

    function _approvalLog(address owner_, address spender, uint256 value)
        internal
        view
        returns (IReactive.LogRecord memory)
    {
        return _approvalLog(owner_, spender, value, address(token));
    }

    function _policyLog(address emitter, bool en, bool unl, uint256 cap)
        internal
        view
        returns (IReactive.LogRecord memory)
    {
        return _log(rc.POLICY_TOPIC(), uint256(uint160(user)), 0, abi.encode(en, unl, cap), emitter, 2);
    }

    function _mirrorPolicy(bool en, bool unl, uint256 cap) internal {
        _react(_policyLog(address(guard), en, unl, cap));
    }

    function _react(IReactive.LogRecord memory l) internal {
        vm.prank(SYSTEM);
        rc.react(l);
    }

    /// @dev a GuardCreated-shaped log, to be emitted by `emitter`
    function _fakeGuardCreated(address emitter, address newGuard) internal view returns (IReactive.LogRecord memory) {
        return _log(
            rc.GUARD_CREATED_TOPIC(),
            uint256(uint160(attacker)),
            uint256(uint160(newGuard)),
            abi.encode(true, true, uint256(0)),
            emitter,
            3
        );
    }

    // ------------------------------------------------------------ constants / ownership
    function test_topicsMatchEventSignatures() public view {
        assertEq(rc.APPROVAL_TOPIC(), uint256(keccak256("Approval(address,address,uint256)")));
        assertEq(rc.POLICY_TOPIC(), uint256(keccak256("ChainGuardPolicySet(address,bool,bool,uint256)")));
        assertEq(rc.GUARD_CREATED_TOPIC(), uint256(keccak256("GuardCreated(address,address,bool,bool,uint256)")));
        assertEq(rc.APPROVAL_TOPIC(), 0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925);
    }

    function test_guardIsApprovalOwner() public {
        vm.prank(user);
        guard.approveToken(address(token), attacker, type(uint256).max);
        assertEq(token.allowance(address(guard), attacker), type(uint256).max);
        assertEq(token.allowance(user, attacker), 0);
    }

    function test_onlyOwnerCanApproveWithdrawSetPolicy() public {
        vm.startPrank(attacker);
        vm.expectRevert(GuardModule.NotOwner.selector);
        guard.approveToken(address(token), attacker, 1);
        vm.expectRevert(GuardModule.NotOwner.selector);
        guard.withdraw(address(token), attacker, 1);
        vm.expectRevert(GuardModule.NotOwner.selector);
        guard.setPolicy(false, false, 0);
        vm.stopPrank();
    }

    function test_ownerCanWithdraw() public {
        vm.prank(user);
        guard.withdraw(address(token), user, 100 ether);
        assertEq(token.balanceOf(user), 100 ether);
    }

    function test_factoryTracksGuardsAndFunds() public {
        vm.deal(user, 1 ether);
        vm.prank(user);
        address g = factory.createGuard{value: 0.1 ether}();
        assertEq(g.balance, 0.1 ether);
        assertEq(factory.guardsOf(user).length, 2);
        assertEq(GuardModule(payable(g)).owner(), user);
    }

    // ------------------------------------------------------------ guard callback auth
    function test_revoke_onlyProxyAndTrustedReactive() public {
        vm.prank(user);
        guard.approveToken(address(token), attacker, type(uint256).max);

        vm.prank(attacker); // not the proxy
        vm.expectRevert();
        guard.revoke(address(rc), address(token), attacker);

        vm.prank(PROXY); // proxy, but wrong injected reactive sender
        vm.expectRevert();
        guard.revoke(attacker, address(token), attacker);

        vm.prank(PROXY); // proxy + correct reactive sender
        guard.revoke(address(rc), address(token), attacker);
        assertEq(token.allowance(address(guard), attacker), 0);
    }

    function test_revoke_idempotentWhenAlreadyZero() public {
        vm.prank(PROXY);
        guard.revoke(address(rc), address(token), attacker); // no revert
    }

    // ------------------------------------------------------------ subscriptions: no wildcard emitters
    function test_constructorMakesNoSubscriptions() public {
        address[] memory t = new address[](1);
        t[0] = address(token);
        uint256 before_ = sys.subsLength();
        new ChainGuardReactive(ORIGIN, t, 3);
        assertEq(sys.subsLength(), before_); // nothing (and in particular no wildcard-emitter policy subscription)
    }

    function test_noSubscriptionHasWildcardEmitterWithoutOwnerFilter() public view {
        for (uint256 i; i < sys.subsLength(); i++) {
            (, address c, uint256 t0, uint256 t1) = sys.subs(i);
            // every subscription is either emitter-specific, or (Approval) owner-specific
            assertTrue(c != address(0) || (t0 == rc.APPROVAL_TOPIC() && t1 != IGNORE));
        }
    }

    function test_setFactory_onlyAdminOnceNonZero() public {
        address[] memory t = new address[](1);
        t[0] = address(token);
        ChainGuardReactive r2 = new ChainGuardReactive(ORIGIN, t, 3);
        vm.prank(attacker);
        vm.expectRevert(ChainGuardReactive.NotAdmin.selector);
        r2.setFactory(address(factory));
        vm.expectRevert(ChainGuardReactive.BadConfig.selector);
        r2.setFactory(address(0));
        uint256 n = sys.subsLength();
        r2.setFactory(address(factory));
        assertEq(sys.subsLength(), n + 1);
        (uint256 c, address a, uint256 t0,) = sys.subs(n);
        assertEq(c, ORIGIN);
        assertEq(a, address(factory));
        assertEq(t0, r2.GUARD_CREATED_TOPIC());
        vm.expectRevert(ChainGuardReactive.FactoryAlreadySet.selector);
        r2.setFactory(address(0xBEEF));
    }

    function test_constructorRejectsBadConfig() public {
        address[] memory none = new address[](0);
        vm.expectRevert(ChainGuardReactive.BadConfig.selector);
        new ChainGuardReactive(ORIGIN, none, 3);
        address[] memory t = new address[](1);
        t[0] = address(token);
        vm.expectRevert(ChainGuardReactive.BadConfig.selector);
        new ChainGuardReactive(ORIGIN, t, 0);
        address[] memory many = new address[](9);
        vm.expectRevert(ChainGuardReactive.BadConfig.selector);
        new ChainGuardReactive(ORIGIN, many, 3);
    }

    // ------------------------------------------------------------ registration (legitimate Guards)
    function test_realFactoryEventRegistersGuardAndSubscribesScoped() public view {
        assertTrue(rc.registered(address(guard)));
        assertEq(rc.guardCount(), 1);
        (bool en, bool unl, uint256 cap) = rc.policies(address(guard)); // initial policy came with GuardCreated
        assertTrue(en);
        assertTrue(unl);
        assertEq(cap, 0);
        // subs: [0] factory GuardCreated, [1] guard policy, [2] spender mode, [3] spender rule (all emitter = guard),
        // [4] token Approval owner = guard
        assertEq(sys.subsLength(), 5);
        (uint256 c1, address a1, uint256 t01,) = sys.subs(1);
        assertEq(c1, ORIGIN);
        assertEq(a1, address(guard));
        assertEq(t01, rc.POLICY_TOPIC());
        (, address a2, uint256 t02, uint256 t12) = sys.subs(4);
        assertEq(a2, address(token));
        assertEq(t02, rc.APPROVAL_TOPIC());
        assertEq(t12, uint256(uint160(address(guard))));
    }

    function test_registrationIsIdempotent() public {
        uint256 n = sys.subsLength();
        vm.recordLogs();
        vm.prank(user);
        factory.createGuard(); // second guard
        Vm.Log[] memory logs = vm.getRecordedLogs();
        IReactive.LogRecord memory rec;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter == address(factory)) rec = _fromVmLog(logs[i]);
        }
        _react(rec);
        assertEq(sys.subsLength(), n + 4);
        _react(rec); // replay
        assertEq(sys.subsLength(), n + 4);
        assertEq(rc.guardCount(), 2);
    }

    function test_maxGuardsCapRejectsExtra() public {
        _createViaFactory(user);
        _createViaFactory(user); // guardCount now 3 == max
        assertEq(rc.guardCount(), 3);
        uint256 n = sys.subsLength();
        address extra = _createViaFactory(user);
        assertFalse(rc.registered(extra));
        assertEq(rc.guardCount(), 3);
        assertEq(sys.subsLength(), n); // no further subscriptions can be forced
    }

    // ------------------------------------------------------------ spoofing / unregistered emitters
    function test_spoofedGuardCreatedFromNonFactoryIgnored() public {
        uint256 n = sys.subsLength();
        _react(_fakeGuardCreated(attacker, attacker)); // attacker contract imitates the factory event
        assertFalse(rc.registered(attacker));
        assertEq(rc.guardCount(), 1);
        assertEq(sys.subsLength(), n);
    }

    function test_guardCreatedIgnoredWhenFactoryUnset() public {
        address[] memory t = new address[](1);
        t[0] = address(token);
        ChainGuardReactive r2 = new ChainGuardReactive(ORIGIN, t, 3);
        IReactive.LogRecord memory l = _fakeGuardCreated(address(0), attacker);
        vm.prank(SYSTEM);
        r2.react(l); // contractAddress == factory == 0 must not match
        assertFalse(r2.registered(attacker));
    }

    function test_policyEventFromUnregisteredEmitterIgnored() public {
        uint256 n = sys.subsLength();
        _react(_policyLog(attacker, true, true, 1)); // not a registered Guard
        (bool en, bool unl, uint256 cap) = rc.policies(attacker);
        assertFalse(en);
        assertFalse(unl);
        assertEq(cap, 0);
        assertEq(sys.subsLength(), n);
    }

    function test_spoofedPolicyCannotChangeRegisteredGuard() public {
        _mirrorPolicy(true, true, 0);
        _react(_policyLog(attacker, false, false, 0));
        (bool en,,) = rc.policies(address(guard));
        assertTrue(en);
    }

    function test_approvalForUnregisteredOwnerNeverRevokes() public {
        _mirrorPolicy(true, true, 0);
        _react(_approvalLog(attacker, attacker, type(uint256).max));
        assertEq(sys.callbackCount(), 0);
    }

    function test_approvalFromUnwatchedTokenNeverRevokes() public {
        _mirrorPolicy(true, true, 0);
        // a fake token claims owner == a registered Guard
        _react(_approvalLog(address(guard), attacker, type(uint256).max, attacker));
        assertEq(sys.callbackCount(), 0);
    }

    function test_react_onlySystem() public {
        IReactive.LogRecord memory l = _approvalLog(address(guard), attacker, 1);
        vm.expectRevert();
        rc.react(l);
    }

    // ------------------------------------------------------------ policy evaluation in react() (registered Guard)
    function test_react_mirrorsPolicyFromRegisteredGuard() public {
        _mirrorPolicy(true, true, 5 ether);
        (bool en, bool unl, uint256 cap) = rc.policies(address(guard));
        assertTrue(en);
        assertTrue(unl);
        assertEq(cap, 5 ether);
    }

    function test_react_revokesUnlimited() public {
        _mirrorPolicy(true, true, 0);
        _react(_approvalLog(address(guard), attacker, type(uint256).max));

        assertEq(sys.callbackCount(), 1);
        (uint256 chainId, address recipient, uint64 gas, bytes memory payload) = sys.lastCallback();
        assertEq(chainId, ORIGIN);
        assertEq(recipient, address(guard));
        assertGt(gas, 0);
        (address placeholder, address tk, address sp) = abi.decode(_args(payload), (address, address, address));
        assertEq(bytes4(payload), GuardModule.revoke.selector);
        assertEq(placeholder, address(0));
        assertEq(tk, address(token));
        assertEq(sp, attacker);
    }

    function test_react_ignoresLimitedApprovalWhenOnlyUnlimitedPolicy() public {
        _mirrorPolicy(true, true, 0);
        _react(_approvalLog(address(guard), attacker, 100 ether));
        assertEq(sys.callbackCount(), 0);
    }

    function test_react_revokesOverCap() public {
        _mirrorPolicy(true, false, 50 ether);
        _react(_approvalLog(address(guard), attacker, 51 ether));
        assertEq(sys.callbackCount(), 1);
        _react(_approvalLog(address(guard), attacker, 50 ether)); // at cap: allowed
        assertEq(sys.callbackCount(), 1);
    }

    function test_react_ignoresDisabledPolicy() public {
        _mirrorPolicy(false, true, 0);
        _react(_approvalLog(address(guard), attacker, type(uint256).max));
        assertEq(sys.callbackCount(), 0);
    }

    function test_react_ignoresNftApprovalAndWrongChain() public {
        _mirrorPolicy(true, true, 0);
        IReactive.LogRecord memory l = _approvalLog(address(guard), attacker, type(uint256).max);
        l.opCode = 4;
        _react(l);
        l.opCode = 3;
        l.chainId = 1;
        _react(l);
        assertEq(sys.callbackCount(), 0);
    }

    /// @dev strips the 4-byte selector
    function _args(bytes memory payload) internal pure returns (bytes memory out) {
        out = new bytes(payload.length - 4);
        for (uint256 i; i < out.length; i++) {
            out[i] = payload[i + 4];
        }
    }

    // ------------------------------------------------------------ registration readiness
    function _newUnconfirmedGuard() internal returns (GuardModule g) {
        g = GuardModule(payable(_createViaFactory(user)));
        assertFalse(g.ready());
    }

    function test_registrationRequestsConfirmationCallbackToGuard() public {
        sys.resetCallbacks();
        GuardModule g = _newUnconfirmedGuard();
        assertEq(sys.callbackCount(), 1);
        (uint256 chainId, address recipient, uint64 gasLimit, bytes memory payload) = sys.lastCallback();
        assertEq(chainId, ORIGIN);
        assertEq(recipient, address(g));
        assertGe(gasLimit, 100_000); // callbacks below 100k gas are ignored by the network
        assertEq(bytes4(payload), GuardModule.confirmRegistered.selector);
        (address placeholder, address[] memory toks) = abi.decode(_args(payload), (address, address[]));
        assertEq(placeholder, address(0)); // network overwrites it with the reactive address
        assertEq(toks.length, 1);
        assertEq(toks[0], address(token));
    }

    function test_guardNotReadyBeforeConfirmation() public {
        GuardModule g = _newUnconfirmedGuard();
        assertFalse(g.protectedToken(address(token)));
    }

    function test_earlyApprovalAndPolicyChangeBlockedUntilConfirmed() public {
        GuardModule g = _newUnconfirmedGuard();
        vm.startPrank(user);
        vm.expectRevert(GuardModule.NotProtected.selector);
        g.approveToken(address(token), attacker, type(uint256).max);
        vm.expectRevert(GuardModule.NotProtected.selector);
        g.setPolicy(true, true, 0);
        vm.stopPrank();
        assertEq(token.allowance(address(g), attacker), 0);
        (bool en, bool unl,) = g.policy();
        assertTrue(en); // default policy untouched
        assertTrue(unl);

        _confirm(address(g));
        assertTrue(g.ready());
        vm.startPrank(user);
        g.setPolicy(true, true, 5 ether);
        g.approveToken(address(token), attacker, 1 ether);
        vm.stopPrank();
        assertEq(token.allowance(address(g), attacker), 1 ether);
    }

    function test_safetyActionsStillWorkBeforeConfirmation() public {
        GuardModule g = _newUnconfirmedGuard();
        token.mint(address(g), 10 ether);
        vm.startPrank(user);
        g.revokeManually(address(token), attacker); // no-op but must not revert
        g.withdraw(address(token), user, 10 ether);
        vm.stopPrank();
        assertEq(token.balanceOf(user), 10 ether);
    }

    function test_confirmationOnlyFromProxyWithTrustedReactive() public {
        GuardModule g = _newUnconfirmedGuard();
        address[] memory toks = new address[](1);
        toks[0] = address(token);
        vm.prank(attacker); // not the proxy
        vm.expectRevert();
        g.confirmRegistered(address(rc), toks);
        vm.prank(PROXY); // proxy but wrong reactive sender
        vm.expectRevert();
        g.confirmRegistered(attacker, toks);
        vm.prank(user); // even the owner cannot self-confirm
        vm.expectRevert();
        g.confirmRegistered(address(rc), toks);
        assertFalse(g.ready());
    }

    function test_confirmationIsIdempotent() public {
        GuardModule g = _newUnconfirmedGuard();
        _confirm(address(g));
        _confirm(address(g));
        assertTrue(g.ready());
        assertTrue(g.protectedToken(address(token)));
    }

    function test_unsupportedTokenBlockedEvenWhenReady() public {
        MockERC20 other = new MockERC20("Other", "OTH");
        assertTrue(guard.ready());
        assertTrue(guard.protectedToken(address(token)));
        assertFalse(guard.protectedToken(address(other)));
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(GuardModule.UnsupportedToken.selector, address(other)));
        guard.approveToken(address(other), attacker, 1);
    }

    function test_noConfirmationForRejectedDuplicateOrSpoofedRegistration() public {
        sys.resetCallbacks();
        // spoofed GuardCreated from a non-factory emitter
        _react(_fakeGuardCreated(attacker, makeAddr("fakeGuard")));
        assertEq(sys.callbackCount(), 0);
        // fill the cap (guardCount: 1 -> 3), then a rejected extra
        _createViaFactory(user);
        _createViaFactory(user);
        assertEq(sys.callbackCount(), 2);
        _createViaFactory(user); // over cap: rejected
        assertEq(sys.callbackCount(), 2);
        // replaying an already-registered Guard's event
        vm.recordLogs();
        vm.prank(user);
        factory.createGuard(); // also over cap
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter == address(factory)) _react(_fromVmLog(logs[i]));
        }
        assertEq(sys.callbackCount(), 2);
    }

    function test_replayedRegistrationDoesNotResendConfirmation() public {
        sys.resetCallbacks();
        vm.recordLogs();
        vm.prank(user);
        factory.createGuard();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        IReactive.LogRecord memory rec;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter == address(factory)) rec = _fromVmLog(logs[i]);
        }
        _react(rec);
        _react(rec);
        assertEq(sys.callbackCount(), 1);
    }

    // ------------------------------------------------------------ spender allowlist (enforced on Lasna)
    function _modeLog(address emitter, bool on) internal view returns (IReactive.LogRecord memory) {
        return _log(rc.SPENDER_MODE_TOPIC(), 0, 0, abi.encode(on), emitter, 1);
    }

    function _ruleLog(address emitter, address spender, bool ok) internal view returns (IReactive.LogRecord memory) {
        return _log(rc.SPENDER_RULE_TOPIC(), uint256(uint160(spender)), 0, abi.encode(ok), emitter, 2);
    }

    function test_spenderTopicsMatchEventSignatures() public view {
        assertEq(rc.SPENDER_MODE_TOPIC(), uint256(keccak256("SpenderModeSet(bool)")));
        assertEq(rc.SPENDER_RULE_TOPIC(), uint256(keccak256("SpenderRuleSet(address,bool)")));
    }

    function test_guardSpenderSettersOnlyOwnerAndReady() public {
        vm.prank(attacker);
        vm.expectRevert(GuardModule.NotOwner.selector);
        guard.setSpenderMode(true);
        vm.prank(attacker);
        vm.expectRevert(GuardModule.NotOwner.selector);
        guard.setSpenderAllowed(attacker, true);

        vm.recordLogs();
        vm.startPrank(user);
        guard.setSpenderMode(true);
        guard.setSpenderAllowed(attacker, true);
        vm.stopPrank();
        assertTrue(guard.restrictSpenders());
        assertTrue(guard.allowedSpender(attacker));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs[0].topics[0], keccak256("SpenderModeSet(bool)"));
        assertEq(logs[1].topics[0], keccak256("SpenderRuleSet(address,bool)"));
    }

    function test_unconfirmedGuardCannotSetSpenderRules() public {
        address g = _createViaFactory(user);
        vm.prank(user);
        vm.expectRevert(GuardModule.NotProtected.selector);
        GuardModule(payable(g)).setSpenderMode(true);
    }

    function test_registrationSubscribesToSpenderEventsOfThatGuardOnly() public view {
        uint256 modeSubs;
        uint256 ruleSubs;
        for (uint256 i; i < sys.subsLength(); i++) {
            (, address c, uint256 t0,) = sys.subs(i);
            if (t0 == rc.SPENDER_MODE_TOPIC()) {
                modeSubs++;
                assertEq(c, address(guard));
            }
            if (t0 == rc.SPENDER_RULE_TOPIC()) {
                ruleSubs++;
                assertEq(c, address(guard));
            }
        }
        assertEq(modeSubs, 1);
        assertEq(ruleSubs, 1);
    }

    function test_spenderRestrictionRevokesSmallApprovalToUnknownSpender() public {
        _mirrorPolicy(true, true, 0); // only unlimited is dangerous...
        _react(_approvalLog(address(guard), attacker, 5 ether));
        assertEq(sys.callbackCount(), 0); // ...so a small approval is fine without the allowlist
        _react(_modeLog(address(guard), true));
        _react(_approvalLog(address(guard), attacker, 5 ether));
        assertEq(sys.callbackCount(), 1);
        (, address recipient,, bytes memory payload) = sys.lastCallback();
        assertEq(recipient, address(guard));
        (, address tk, address sp) = abi.decode(_args(payload), (address, address, address));
        assertEq(tk, address(token));
        assertEq(sp, attacker);
    }

    function test_allowlistedSpenderKeepsSmallButNotUnlimitedApproval() public {
        _mirrorPolicy(true, true, 0);
        _react(_modeLog(address(guard), true));
        _react(_ruleLog(address(guard), attacker, true));
        _react(_approvalLog(address(guard), attacker, 5 ether));
        assertEq(sys.callbackCount(), 0);
        _react(_approvalLog(address(guard), attacker, type(uint256).max)); // unlimited rule still applies
        assertEq(sys.callbackCount(), 1);
        _react(_ruleLog(address(guard), attacker, false)); // removing it re-arms the restriction
        _react(_approvalLog(address(guard), attacker, 5 ether));
        assertEq(sys.callbackCount(), 2);
    }

    function test_zeroApprovalNeverTriggersRevoke() public {
        _mirrorPolicy(true, true, 0);
        _react(_modeLog(address(guard), true));
        _react(_approvalLog(address(guard), attacker, 0)); // our own revoke emits Approval(..., 0)
        assertEq(sys.callbackCount(), 0);
    }

    function test_disabledPolicyOverridesSpenderRestriction() public {
        _mirrorPolicy(false, true, 0);
        _react(_modeLog(address(guard), true));
        _react(_approvalLog(address(guard), attacker, 5 ether));
        assertEq(sys.callbackCount(), 0);
    }

    function test_spoofedSpenderEventsFromUnregisteredEmitterIgnored() public {
        address fake = makeAddr("fakeGuard");
        _react(_modeLog(fake, true));
        _react(_ruleLog(fake, attacker, true));
        assertFalse(rc.restrictSpenders(fake));
        assertFalse(rc.spenderAllowed(fake, attacker));
        // and they cannot touch a real Guard's rules
        _react(_modeLog(address(guard), true));
        _react(_ruleLog(fake, attacker, true));
        assertFalse(rc.spenderAllowed(address(guard), attacker));
    }
}
