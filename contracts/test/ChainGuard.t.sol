// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {IReactive} from "@reactive/src/interfaces/IReactive.sol";
import {IPayable} from "@reactive/src/interfaces/IPayable.sol";
import {ISystemContract} from "@reactive/src/interfaces/ISystemContract.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {GuardModule} from "../src/GuardModule.sol";
import {GuardFactory} from "../src/GuardFactory.sol";
import {ChainGuardReactive} from "../src/reactive/ChainGuardReactive.sol";
import {MockSystem} from "./mocks/MockSystem.sol";

contract ChainGuardTest is Test {
    address constant SYSTEM = 0x8888888888888888888888888888888888888888;
    address constant PROXY = 0x476F44b11F5C942c58f4c8E3d0300E5710743585;
    uint256 constant ORIGIN = 84532;

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
        rc = new ChainGuardReactive(ORIGIN, tokens);
        factory = new GuardFactory(IPayable(payable(PROXY)), address(rc));
        vm.prank(user);
        guard = GuardModule(payable(factory.createGuard()));
        token.mint(address(guard), 1_000 ether);
    }

    // ------------------------------------------------------------ helpers
    function _log(
        uint256 topic0,
        uint256 t1,
        uint256 t2,
        bytes memory data,
        address emitter,
        uint256 opCode
    ) internal pure returns (IReactive.LogRecord memory) {
        return IReactive.LogRecord(ORIGIN, emitter, topic0, t1, t2, 0, data, 1, opCode, 0, 0xabc, 0);
    }

    function _approvalLog(address owner_, address spender, uint256 value)
        internal
        view
        returns (IReactive.LogRecord memory)
    {
        return _log(
            rc.APPROVAL_TOPIC(),
            uint256(uint160(owner_)),
            uint256(uint160(spender)),
            abi.encode(value),
            address(token),
            3
        );
    }

    function _mirrorPolicy(bool en, bool unl, uint256 cap) internal {
        _react(
            _log(
                rc.POLICY_TOPIC(),
                uint256(uint160(user)),
                0,
                abi.encode(en, unl, cap),
                address(guard),
                2
            )
        );
    }

    function _react(IReactive.LogRecord memory l) internal {
        vm.prank(SYSTEM);
        rc.react(l);
    }

    // ------------------------------------------------------------ constants / ownership
    function test_topicsMatchEventSignatures() public view {
        assertEq(rc.APPROVAL_TOPIC(), uint256(keccak256("Approval(address,address,uint256)")));
        assertEq(
            rc.POLICY_TOPIC(), uint256(keccak256("ChainGuardPolicySet(address,bool,bool,uint256)"))
        );
        assertEq(
            uint256(rc.APPROVAL_TOPIC()),
            0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925
        );
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

        // not the proxy
        vm.prank(attacker);
        vm.expectRevert();
        guard.revoke(address(rc), address(token), attacker);

        // proxy but wrong injected reactive sender
        vm.prank(PROXY);
        vm.expectRevert();
        guard.revoke(attacker, address(token), attacker);

        // proxy + correct reactive sender
        vm.prank(PROXY);
        guard.revoke(address(rc), address(token), attacker);
        assertEq(token.allowance(address(guard), attacker), 0);
    }

    function test_revoke_idempotentWhenAlreadyZero() public {
        vm.prank(PROXY);
        guard.revoke(address(rc), address(token), attacker); // no revert
    }

    // ------------------------------------------------------------ reactive subscriptions
    function test_constructorSubscribes() public view {
        assertEq(sys.subsLength(), 2); // policy wildcard + watched token
        (uint256 c0, address a0, uint256 t0) = sys.subs(0);
        assertEq(c0, ORIGIN);
        assertEq(a0, address(0));
        assertEq(t0, rc.POLICY_TOPIC());
        (, address a1, uint256 t1) = sys.subs(1);
        assertEq(a1, address(token));
        assertEq(t1, rc.APPROVAL_TOPIC());
    }

    function test_react_onlySystem() public {
        IReactive.LogRecord memory l = _approvalLog(address(guard), attacker, 1);
        vm.expectRevert();
        rc.react(l);
    }

    // ------------------------------------------------------------ policy evaluation in react()
    function test_react_mirrorsPolicyKeyedByEmitter() public {
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
        // first arg is the address(0) placeholder; selector + (token, spender) intact
        (address placeholder, address tk, address sp) =
            abi.decode(_args(payload), (address, address, address));
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

    function test_react_ignoresDisabledOrUnknownGuard() public {
        _mirrorPolicy(false, true, 0);
        _react(_approvalLog(address(guard), attacker, type(uint256).max));
        // an owner with no policy at all
        _react(_approvalLog(attacker, attacker, type(uint256).max));
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

    function test_spoofedPolicyEventOnlyAffectsEmitter() public {
        // attacker contract emits a "policy" for itself; the real guard's policy is untouched
        _mirrorPolicy(true, true, 0);
        _react(
            _log(
                rc.POLICY_TOPIC(),
                uint256(uint160(user)),
                0,
                abi.encode(false, false, uint256(0)),
                attacker,
                2
            )
        );
        (bool en,,) = rc.policies(address(guard));
        assertTrue(en);
    }

    function test_adminOnlyWatch() public {
        vm.prank(attacker);
        vm.expectRevert(ChainGuardReactive.NotAdmin.selector);
        rc.watchToken(address(0xBEEF));
        rc.watchToken(address(0xBEEF));
        assertEq(sys.subsLength(), 3);
    }

    /// @dev strips the 4-byte selector
    function _args(bytes memory payload) internal pure returns (bytes memory out) {
        out = new bytes(payload.length - 4);
        for (uint256 i; i < out.length; i++) {
            out[i] = payload[i + 4];
        }
    }
}
