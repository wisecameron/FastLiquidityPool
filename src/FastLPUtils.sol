//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

library FastLPUtils
{
    /// Efficient sqrt from: 
    /// https://ethereum-magicians.org/t/eip-7054-gas-efficient-square-root-calculation-with-binary-search-approach/14539/2
    /// Converted to Yul 
    function sqrt(uint256 x) public pure returns (uint128) {

        /// @solidity memory-safe-assembly
        assembly
        {
            if iszero(x)
            {
                return(0x0, 0x0)
            }

            let xx := x
            let r := 1

            // estimate bit length to get a good approximation for r
            // Intuition: the sqrt of a value covers roughly half of its bit length
            if gt(xx, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)
            {
                xx := shr(128, xx)
                r := shl(64, r)
            }
            if gt(xx, 0xFFFFFFFFFFFFFFFF)
            {
                xx := shr(64, xx)
                r := shl(32, r)
            }
            if gt(xx, 0xFFFFFFFF)
            {
                xx := shr(32, xx)
                r := shl(16, r)
            }
            if gt(xx, 0xFFFF)
            {
                xx := shr(16, xx)
                r := shl(8, r)
            }
            if gt(xx, 0xFF)
            {
                xx := shr(8, xx)
                r := shl(4, r)
            }
            if gt(xx, 0xF)
            {
                xx := shr(4, xx)
                r := shl(2, r)
            }
            if gt(xx, 0x7)
            {
                r := shl(1, r)
            }

            //Newton-Rahphson iterations
            r := shr(
                1, add(
                    r, div(x, r)
                )
            )

            r := shr(
                1, add(
                    r, div(x, r)
                )
            )

            r := shr(
                1, add(
                    r, div(x, r)
                )
            )

            r := shr(
                1, add(
                    r, div(x, r)
                )
            )

            r := shr(
                1, add(
                    r, div(x, r)
                )
            )

            r := shr(
                1, add(
                    r, div(x, r)
                )
            )

            r := shr(
                1, add(
                    r, div(x, r)
                )
            )

            let r1 := div(x, r)

            if lt(r, r1)
            {
                mstore(0x0, r)
                return(0x0, 0x20)
            }
            mstore(0x0, r1)
            return(0x0, 0x20)
        }
    }
}