// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice The seven basket ids. Bytes are the UTF-8 name, right-padded.
library Constituents {
    bytes32 internal constant DAI = "DAI";
    bytes32 internal constant TRAC = "TRAC";
    bytes32 internal constant RENDER = "RENDER";
    bytes32 internal constant LPT = "LPT";
    bytes32 internal constant IRYS = "IRYS";
    bytes32 internal constant AKT = "AKT";
    bytes32 internal constant RITUAL = "RITUAL";

    function all() internal pure returns (bytes32[7] memory ids) {
        ids[0] = DAI;
        ids[1] = TRAC;
        ids[2] = RENDER;
        ids[3] = LPT;
        ids[4] = IRYS;
        ids[5] = AKT;
        ids[6] = RITUAL;
    }

    function isKnown(bytes32 id) internal pure returns (bool) {
        return id == DAI || id == TRAC || id == RENDER || id == LPT || id == IRYS || id == AKT
            || id == RITUAL;
    }

    function isPush(bytes32 id) internal pure returns (bool) {
        return id == AKT || id == RITUAL;
    }

    function isPool(bytes32 id) internal pure returns (bool) {
        return id == TRAC || id == RENDER || id == LPT || id == IRYS;
    }
}
