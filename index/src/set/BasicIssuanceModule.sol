// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISetToken} from "./ISetToken.sol";
import {PreciseUnitMath} from "./PreciseUnitMath.sol";
import {TokenLib} from "../libraries/TokenLib.sol";

/// @notice Set Protocol v2 BasicIssuanceModule.
///         Issue pulls each component into the set and mints shares.
///         The required amount is ceil(realUnit * quantity / 1e18).
contract BasicIssuanceModule {
    event SetIssued(address indexed setToken, address indexed issuer, address indexed to, uint256 quantity);
    event SetRedeemed(address indexed setToken, address indexed redeemer, address indexed to, uint256 quantity);

    function initialize(ISetToken setToken) external {
        require(msg.sender == setToken.manager(), "manager");
        setToken.initializeModule();
    }

    function issue(ISetToken setToken, uint256 quantity, address to) external {
        require(quantity > 0, "qty");
        (address[] memory components, uint256[] memory amounts) = getRequiredComponentIssuanceUnits(setToken, quantity);
        for (uint256 i; i < components.length; i++) {
            if (amounts[i] > 0) {
                TokenLib.safeTransferFrom(components[i], msg.sender, address(setToken), amounts[i]);
            }
        }
        setToken.mint(to, quantity);
        emit SetIssued(address(setToken), msg.sender, to, quantity);
    }

    function redeem(ISetToken setToken, uint256 quantity, address to) external {
        require(quantity > 0 && to != address(0), "qty");
        (address[] memory components, uint256[] memory amounts) = getRequiredComponentIssuanceUnits(setToken, quantity);
        setToken.burn(msg.sender, quantity);
        for (uint256 i; i < components.length; i++) {
            if (amounts[i] == 0) continue;
            setToken.invoke(components[i], 0, abi.encodeWithSignature("transfer(address,uint256)", to, amounts[i]));
        }
        emit SetRedeemed(address(setToken), msg.sender, to, quantity);
    }

    function getRequiredComponentIssuanceUnits(ISetToken setToken, uint256 quantity)
        public
        view
        returns (address[] memory components, uint256[] memory amounts)
    {
        components = setToken.getComponents();
        amounts = new uint256[](components.length);
        for (uint256 i; i < components.length; i++) {
            int256 realUnit = setToken.getDefaultPositionRealUnit(components[i]);
            require(realUnit > 0, "unit");
            amounts[i] = PreciseUnitMath.preciseMulCeil(uint256(realUnit), quantity);
        }
    }
}
