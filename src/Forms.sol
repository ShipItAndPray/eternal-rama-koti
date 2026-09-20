// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library Forms {
    uint8 internal constant COUNT = 10;
    error BadLang();

    function form(uint8 i) internal pure returns (string memory) {
        if (i == 0) return unicode"శ్రీరామ";
        if (i == 1) return unicode"श्रीराम";
        if (i == 2) return unicode"ஸ்ரீராம";
        if (i == 3) return unicode"ಶ್ರೀರಾಮ";
        if (i == 4) return unicode"ശ്രീരാമ";
        if (i == 5) return unicode"শ্রীরাম";
        if (i == 6) return unicode"શ્રીરામ";
        if (i == 7) return unicode"ଶ୍ରୀରାମ";
        if (i == 8) return unicode"ਸ਼੍ਰੀਰਾਮ";
        if (i == 9) return "Sri Rama";
        revert BadLang();
    }

    function language(uint8 i) internal pure returns (string memory) {
        if (i == 0) return "Telugu";
        if (i == 1) return "Hindi";
        if (i == 2) return "Tamil";
        if (i == 3) return "Kannada";
        if (i == 4) return "Malayalam";
        if (i == 5) return "Bengali";
        if (i == 6) return "Gujarati";
        if (i == 7) return "Odia";
        if (i == 8) return "Punjabi";
        if (i == 9) return "English";
        revert BadLang();
    }
}
