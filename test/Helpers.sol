// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Vm} from "forge-std/Vm.sol";
import {DataStore} from "../src/lib/DataStore.sol";
import {Forms} from "../src/Forms.sol";
import {EternalRamaKoti} from "../src/EternalRamaKoti.sol";

library Helpers {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    function deployKoti() internal returns (EternalRamaKoti k) {
        address[3] memory g;
        for (uint8 i = 0; i < Forms.COUNT; i++) {
            g[i] = DataStore.put(bytes(vm.readFile(string.concat("glyphs/", vm.toString(i), ".txt"))));
        }
        k = new EternalRamaKoti(g);
    }
}
