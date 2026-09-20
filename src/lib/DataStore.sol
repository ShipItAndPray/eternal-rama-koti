// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// Stores raw bytes as a contract's runtime code (prefixed with STOP) and reads them back.
library DataStore {
    error CreateFailed();

    function put(bytes memory data) internal returns (address p) {
        // initcode: copy everything after the 11-byte header to memory and return it as runtime code
        bytes memory code = abi.encodePacked(hex"600B5981380380925939F3", hex"00", data);
        assembly { p := create(0, add(code, 32), mload(code)) }
        if (p == address(0)) revert CreateFailed();
    }

    function get(address p) internal view returns (bytes memory out) {
        uint256 size;
        assembly { size := extcodesize(p) }
        size -= 1;
        out = new bytes(size);
        assembly { extcodecopy(p, add(out, 32), 1, size) }
    }
}
