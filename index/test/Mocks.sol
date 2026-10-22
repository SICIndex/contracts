// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _move(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            require(allowed >= amount, "allowance");
            allowance[from][msg.sender] = allowed - amount;
        }
        _move(from, to, amount);
        return true;
    }

    function _move(address from, address to, uint256 amount) internal {
        require(balanceOf[from] >= amount, "balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }
}

contract Puller {
    bool public called;

    function pull(address token, uint256 amount) external {
        called = true;
        MockERC20(token).transferFrom(msg.sender, address(this), amount);
    }

    function fail() external pure {
        revert("no");
    }
}

contract MockV2 {
    address public token0;
    address public token1;
    uint112 public r0;
    uint112 public r1;

    constructor(address a, address b) {
        require(a != b && a != address(0) && b != address(0), "pair");
        if (a < b) {
            token0 = a;
            token1 = b;
        } else {
            token0 = b;
            token1 = a;
        }
    }

    function set(address token, uint112 amount, address other, uint112 otherAmount) external {
        if (token == token0 && other == token1) {
            r0 = amount;
            r1 = otherAmount;
        } else if (token == token1 && other == token0) {
            r1 = amount;
            r0 = otherAmount;
        } else {
            revert("tokens");
        }
    }

    function getReserves() external view returns (uint112, uint112, uint32) {
        return (r0, r1, 0);
    }
}

contract MockV3 {
    address public token0;
    address public token1;
    int56 public thenCum;
    int56 public nowCum;

    constructor(address a, address b) {
        require(a != b, "pair");
        if (a < b) {
            token0 = a;
            token1 = b;
        } else {
            token0 = b;
            token1 = a;
        }
    }

    function setTick(int24 tick) external {
        nowCum = int56(tick) * 1800;
    }

    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (int56[] memory cumulatives, uint160[] memory liquidity)
    {
        require(secondsAgos.length == 2 && secondsAgos[0] == 1800 && secondsAgos[1] == 0, "window");
        cumulatives = new int56[](2);
        cumulatives[0] = thenCum;
        cumulatives[1] = nowCum;
        liquidity = new uint160[](2);
    }
}
