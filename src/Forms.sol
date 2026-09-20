// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// The canonical written forms. Fixed forever at deploy.
library Forms {
    uint8 internal constant COUNT = 6;
    error BadLang();

    function form(uint8 i) internal pure returns (string memory) {
        if (i == 0) return unicode"శ్రీరామ";
        if (i == 1) return unicode"ஸ்ரீ ராம ஜெயம்";
        if (i == 2) return unicode"राम";
        if (i == 3) return "Sri Rama";
        if (i == 4) return "Sri Rama Jayam";
        if (i == 5) return "Ram";
        revert BadLang();
    }

    function language(uint8 i) internal pure returns (string memory) {
        if (i == 0) return "Telugu";
        if (i == 1) return "Tamil";
        if (i == 2) return "Hindi";
        if (i < COUNT) return "English";
        revert BadLang();
    }

    /// The regional tradition a form belongs to, whatever script it is written in.
    function tradition(uint8 i) internal pure returns (string memory) {
        if (i == 0 || i == 3) return "Telugu";
        if (i == 1 || i == 4) return "Tamil";
        if (i == 2 || i == 5) return "Hindi";
        revert BadLang();
    }
}
