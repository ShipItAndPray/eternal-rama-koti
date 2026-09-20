// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Base64} from "./lib/Base64.sol";

library Renderer {
    uint256 internal constant KOTI = 10_000_000;

    function u(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        uint256 t = v; uint256 n;
        while (t != 0) { n++; t /= 10; }
        bytes memory b = new bytes(n);
        while (v != 0) { b[--n] = bytes1(uint8(48 + v % 10)); v /= 10; }
        return string(b);
    }

    /// Indian digit grouping: last group of 3, then groups of 2.
    function indian(uint256 v) internal pure returns (string memory) {
        bytes memory d = bytes(u(v));
        if (d.length <= 3) return string(d);
        uint256 rest = d.length - 3;
        uint256 commas = 1 + (rest - 1) / 2;
        bytes memory out = new bytes(d.length + commas);
        uint256 o = out.length; uint256 i = d.length;
        for (uint256 k = 0; k < 3; k++) out[--o] = d[--i];
        while (i > 0) {
            out[--o] = ",";
            out[--o] = d[--i];
            if (i > 0) out[--o] = d[--i];
        }
        return string(out);
    }

    function hexAddr(address a) internal pure returns (string memory) {
        bytes16 hexd = "0123456789abcdef";
        bytes memory s = new bytes(42);
        s[0] = "0"; s[1] = "x";
        uint160 v = uint160(a);
        for (uint256 i = 41; i > 1; i--) { s[i] = hexd[v & 0xf]; v >>= 4; }
        return string(s);
    }

    function svg(bytes memory d, string memory name, uint256 id) internal pure returns (string memory) {
        string memory koti = id > KOTI
            ? string.concat("<text x=\"300\" y=\"672\" text-anchor=\"middle\" font-family=\"serif\" font-size=\"24\" fill=\"#7A5A3A\">Koti ", u((id - 1) / KOTI + 1), "</text>")
            : "";
        return string.concat(
            "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 600 800\">",
            "<rect width=\"600\" height=\"800\" fill=\"#FBF3E4\"/>",
            "<rect x=\"24\" y=\"24\" width=\"552\" height=\"752\" fill=\"none\" stroke=\"#E0891F\" stroke-width=\"4\"/>",
            "<svg x=\"50\" y=\"200\" width=\"500\" height=\"200\" viewBox=\"0 0 1000 400\"><path d=\"", string(d), "\" fill=\"#9B1C1C\"/></svg>",
            "<text x=\"300\" y=\"560\" text-anchor=\"middle\" font-family=\"serif\" font-size=\"34\" fill=\"#3A2A1A\">", name, "</text>",
            "<text x=\"300\" y=\"620\" text-anchor=\"middle\" font-family=\"serif\" font-size=\"26\" fill=\"#7A5A3A\">#", indian(id), " of 1,00,00,000</text>",
            koti,
            "</svg>"
        );
    }

    function json(
        string memory form, string memory language, string memory name, address writer,
        uint256 id, uint40 ts, string memory svgStr
    ) internal pure returns (string memory) {
        string memory img = string.concat("data:image/svg+xml;base64,", Base64.encode(bytes(svgStr)));
        string memory j = string.concat(
            "{\"name\":\"", form, " #", indian(id), "\",",
            "\"description\":\"One name of Rama, written by ", name, " on Ethereum. Entry ", indian(id), " of the Eternal Rama Koti.\",",
            "\"image\":\"", img, "\",",
            "\"attributes\":[",
            "{\"trait_type\":\"Language\",\"value\":\"", language, "\"},",
            "{\"trait_type\":\"Written by\",\"value\":\"", name, "\"},",
            "{\"trait_type\":\"Writer\",\"value\":\"", hexAddr(writer), "\"},",
            "{\"trait_type\":\"Index\",\"display_type\":\"number\",\"value\":", u(id), "},",
            "{\"trait_type\":\"Koti\",\"display_type\":\"number\",\"value\":", u((id - 1) / KOTI + 1), "},",
            "{\"trait_type\":\"Timestamp\",\"display_type\":\"date\",\"value\":", u(ts), "}",
            "]}"
        );
        return string.concat("data:application/json;base64,", Base64.encode(bytes(j)));
    }
}
