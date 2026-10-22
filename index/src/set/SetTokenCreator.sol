// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Controller} from "./Controller.sol";
import {SetToken} from "./SetToken.sol";

/// @notice Set Protocol v2 factory. Deploys a set and registers it on the controller.
contract SetTokenCreator {
    Controller public immutable controller;

    constructor(Controller controller_) {
        require(address(controller_) != address(0), "zero");
        controller = controller_;
    }

    function create(
        address[] calldata components,
        int256[] calldata units,
        address[] calldata modules,
        address manager,
        string calldata name,
        string calldata symbol
    ) external returns (address) {
        SetToken setToken = new SetToken(controller, manager, name, symbol);
        setToken.initialize(components, units, modules);
        controller.addSet(address(setToken));
        return address(setToken);
    }
}
