// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// The canonical written forms. Fixed forever at deploy.
library Forms {
    uint8 internal constant COUNT = 3;
    error BadLang();

    function form(uint8 i) internal pure returns (string memory) {
        if (i == 0) return unicode"శ్రీరామ";
        if (i == 1) return unicode"ஸ்ரீ ராம ஜெயம்";
        if (i == 2) return unicode"राम";
        revert BadLang();
    }

    function language(uint8 i) internal pure returns (string memory) {
        if (i == 0) return "Telugu";
        if (i == 1) return "Tamil";
        if (i == 2) return "Hindi";
        revert BadLang();
    }
}
