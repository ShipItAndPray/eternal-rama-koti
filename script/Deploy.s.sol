// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Script, console2} from "forge-std/Script.sol";
import {DataStore} from "../src/lib/DataStore.sol";
import {Forms} from "../src/Forms.sol";
import {EternalRamaKoti} from "../src/EternalRamaKoti.sol";

contract Deploy is Script {
    function run() external {
        vm.startBroadcast(); // signer comes from --account (keystore) or --private-key
        address[6] memory g;
        for (uint8 i = 0; i < Forms.COUNT; i++) {
            g[i] = DataStore.put(bytes(vm.readFile(string.concat("glyphs/", vm.toString(i), ".txt"))));
            console2.log("glyph", i, g[i]);
        }
        EternalRamaKoti k = new EternalRamaKoti(g);
        vm.stopBroadcast();
        console2.log("EternalRamaKoti", address(k));
    }
}
