// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ILayerZeroEndpointV2} from "./interfaces/ILayerZero.sol";

/// @notice DAI as a LayerZero V2 OFT. Deployed on Ethereum. Peers on other chains are wired later.
/// @dev The name is the product coin. This is not MakerDAO DAI. The endpoint address is injected.
contract DaiOFT {
    string public constant name = "Decentralized Artificial Intelligence";
    string public constant symbol = "DAI";
    uint8 public constant decimals = 18;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    address public immutable endpoint;
    address public owner;
    mapping(uint32 => bytes32) public peers;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);
    event PeerSet(uint32 indexed eid, bytes32 peer);
    event OwnerSet(address indexed owner);
    event OftSent(uint32 indexed dstEid, bytes32 to, uint256 amount);
    event OftReceived(uint32 indexed srcEid, address indexed to, uint256 amount);

    error NotOwner();
    error NotEndpoint();
    error PeerUnset();
    error BadPeer();
    error ZeroAddress();

    constructor(address endpoint_, uint256 initialMint) {
        if (endpoint_ == address(0)) revert ZeroAddress();
        endpoint = endpoint_;
        owner = msg.sender;
        if (initialMint > 0) _mint(msg.sender, initialMint);
    }

    function setOwner(address next) external {
        if (msg.sender != owner) revert NotOwner();
        if (next == address(0)) revert ZeroAddress();
        owner = next;
        emit OwnerSet(next);
    }

    /// @notice Wire another chain. `peer` is the remote OFT address, left-padded to bytes32.
    function setPeer(uint32 eid, bytes32 peer) external {
        if (msg.sender != owner) revert NotOwner();
        if (peer == bytes32(0)) revert BadPeer();
        peers[eid] = peer;
        emit PeerSet(eid, peer);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    /// @notice Burn locally and send the amount through LayerZero. Refunds unused native fee to `msg.sender`.
    function send(uint32 dstEid, bytes32 to, uint256 amount, bytes calldata options) external payable {
        bytes32 peer = peers[dstEid];
        if (peer == bytes32(0)) revert PeerUnset();
        if (to == bytes32(0)) revert ZeroAddress();
        _burn(msg.sender, amount);
        ILayerZeroEndpointV2.MessagingParams memory params = ILayerZeroEndpointV2.MessagingParams({
            dstEid: dstEid,
            receiver: peer,
            message: abi.encode(to, amount),
            options: options,
            payInLzToken: false
        });
        ILayerZeroEndpointV2(endpoint).send{value: msg.value}(params, msg.sender);
        emit OftSent(dstEid, to, amount);
    }

    /// @notice LayerZero entry. Only the endpoint, and only from a configured peer.
    function lzReceive(
        ILayerZeroEndpointV2.Origin calldata origin,
        bytes32,
        bytes calldata message,
        address,
        bytes calldata
    ) external {
        if (msg.sender != endpoint) revert NotEndpoint();
        if (peers[origin.srcEid] != origin.sender) revert BadPeer();
        (bytes32 toWord, uint256 amount) = abi.decode(message, (bytes32, uint256));
        address to = address(uint160(uint256(toWord)));
        if (to == address(0)) revert ZeroAddress();
        _mint(to, amount);
        emit OftReceived(origin.srcEid, to, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        if (to == address(0)) revert ZeroAddress();
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) internal {
        if (to == address(0)) revert ZeroAddress();
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal {
        balanceOf[from] -= amount;
        totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }
}
