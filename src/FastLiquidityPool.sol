//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/// @title Fast, Minimal Liquidity Pool Implementation -- Based on Uni v2 logic
/// @author Cameron Warnick @wisecameron
/// @notice No super unique tricks here, but it is a good reference for fundamental Yul operations.
/// @notice This is aggressively-optimized, but not optimal.


import '../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import './FastLP.sol';
import {FastLPUtils} from './FastLPUtils.sol';

contract FastLiquidityPool
{
    IERC20 public pooledTokenA;
    IERC20 public pooledTokenB;
    FastLP public lpToken;

    uint256 public tokenAQuantityInReserve;
    uint256 public tokenBQuantityInReserve;
    uint256 private fee;
    bool private locked;

    constructor(
        address _tokenA,
        address _tokenB
    )
    {
        pooledTokenA = IERC20(_tokenA);
        pooledTokenB = IERC20(_tokenB);
        lpToken = new FastLP();
    }

    modifier ReentrancyGuard
    {
        /// @solidity memory-safe-assembly
        assembly
        {
            //Reentrancy detected!
            if iszero(xor(sload(locked.slot), 0x1))
            {
                mstore(0x0, 0x5265656e7472616e6379206465746563746564210000000000000000000000)
                revert(0x0, 0x14)
            }
            sstore(locked.slot, 1)
        }

        _;

        /// @solidity memory-safe-assembly
        assembly
        {
            sstore(locked.slot, 0)
        }
    }

    function set_fee(uint256 newFee)
    external
    {
        require(newFee < 1000, "fee too high!");
        fee = newFee;
    }

    function _update_reserves(
        uint256 newAmountInReserveA,
        uint256 newAmountInReserveB
    ) private 
    {
        tokenAQuantityInReserve = newAmountInReserveA;
        tokenBQuantityInReserve = newAmountInReserveB;
    }

    /// @notice LP tokens minted differs based on its current supply.
    /// if supply is zero, it is sqrt(amountA * amountB)
    /// else, it is the min between amount A and B of the result derived from 
    /// (amountA * lpTotalSupply) / tokenAReserves
    /// This is to prevent abuse in unbalanced pools.
    function add_liquidity(uint256 amountA, uint256 amountB)
    external ReentrancyGuard
    returns(uint256 lpTokensReceivedByUser)
    {
        uint256 tokenAReserveBalance;
        uint256 tokenBReserveBalance;
        uint256 lpTokenTotalSupply = lpToken.totalSupply();

        if(lpTokenTotalSupply == 0) lpTokensReceivedByUser = FastLPUtils.sqrt(amountA * amountB);
        else
        {
            /// @solidity memory-safe-assembly
            assembly
            {
                //transfer amountA, amountB from caller to this //
                // Transfer amountA
                let freePtr := mload(0x40)
                mstore(freePtr, 0x23b872dd00000000000000000000000000000000000000000000000000000000)
                mstore(add(freePtr, 0x04), caller())
                mstore(add(freePtr, 0x24), address())
                mstore(add(freePtr, 0x44), amountA)

                let success := call(
                    gas(),
                    sload(pooledTokenA.slot),
                    0,
                    freePtr,
                    0x64,
                    0x00,
                    0x00
                )

                //Failed transferFrom
                if iszero(success)
                {
                    mstore(0x00, 0x4661696c6564207472616e7366657246726f6d00000000000000000000000000)
                    revert(0x0, 0x13)
                }

                mstore(add(freePtr, 0x44), amountB)
                success := call(
                    gas(),
                    sload(pooledTokenB.slot),
                    0,
                    freePtr,
                    0x64,
                    0x00,
                    0x00
                )

                //Failed transferFrom
                if iszero(success)
                {
                    mstore(0x00, 0x4661696c6564207472616e7366657246726f6d00000000000000000000000000)
                    revert(0x0, 0x13)
                }

                tokenAReserveBalance := sload(tokenAQuantityInReserve.slot)
                tokenBReserveBalance := sload(tokenBQuantityInReserve.slot)

                let lpAmountDerivedFromAmountA := div(
                    mul(amountA, lpTokenTotalSupply),
                    sload(tokenAQuantityInReserve.slot)
                )

                let lpAmountDerivedFromAmountB := div(
                    mul(amountB, lpTokenTotalSupply),
                    sload(tokenAQuantityInReserve.slot)
                )

                if gt(lpAmountDerivedFromAmountA, lpAmountDerivedFromAmountB)
                {
                    lpTokensReceivedByUser := lpAmountDerivedFromAmountB
                }
                if iszero(gt(lpAmountDerivedFromAmountA, lpAmountDerivedFromAmountB))
                {
                    lpTokensReceivedByUser := lpAmountDerivedFromAmountA
                }

                if iszero(lpTokensReceivedByUser)
                {
                    //Can't mint zero lp tokens
                    mstore(0x0, 0x43616e27742072656365697665207a65726f20746f6b656e73210000000000)
                    revert(0x0, 26)
                }

                //call lpToken.mint(msg.sender, lpTokensReceivedByUser)
                mstore(freePtr, 0x40c10f1900000000000000000000000000000000000000000000000000000000)
                mstore(add(freePtr, 0x04), caller())
                mstore(add(freePtr, 0x24), lpTokensReceivedByUser)
                success := call(
                    gas(),
                    sload(lpToken.slot),
                    0,
                    freePtr,
                    0x44,
                    0x00,
                    0x00
                )

                //Failed to mint!
                if iszero(success)
                {
                    mstore(0x0, 0x4661696c656420746f206d696e742100000000000000000000000000000000)
                    revert(0x0, 0x0F)
                }
            }
        }

        _update_reserves(amountA + tokenAReserveBalance, amountB + tokenBReserveBalance);
    }

    function remove_liquidity(uint256 lpAmount)
    external ReentrancyGuard
    returns(uint256 amountA, uint256 amountB)
    {
        uint256 pooledA = tokenAQuantityInReserve;
        uint256 pooledB = tokenBQuantityInReserve;
        address tokenA = address(pooledTokenA);
        address tokenB = address(pooledTokenB);

        assembly
        {
            //get lpToken total supply
            let freePtr := mload(0x40)
            mstore(freePtr, 0x18160ddd00000000000000000000000000000000000000000000000000000000)

            let success := call(
                gas(),
                sload(lpToken.slot),
                0x00,
                freePtr,
                0x04,
                add(freePtr, 0x04),
                0x20
            )

            if iszero(success)
            {
                //Failed to get lp total supply!
                mstore(0x0, 0x4661696c656420746f20676574206c7020746f74616c20737570706c79210000)
                revert(0x0, 0x1D)
            }

            let lpTokenTotalSupply := mload(add(freePtr, 0x04))

            //Zero lp token supply!
            if iszero(lpTokenTotalSupply)
            {
                mstore(0x0, 0x5a65726f206c7020746f6b656e20737570706c792100000000000000000000)
                revert(0x0, 0x15)
            }

            //send LP fees (proportional)
            //get tokenA/B.balanceOf(address(this))
            mstore(freePtr, 0x70a0823100000000000000000000000000000000000000000000000000000000)
            mstore(add(freePtr, 0x04), address())

            success := call(
                gas(),
                tokenA,
                0x00,
                freePtr,
                0x24,
                add(freePtr, 0x24),
                0x20
            )

            if iszero(success)
            {
                mstore(0x0, 0x4661696c656420746f206765742062616c616e63652100000000000000000000)
                revert(0x0, 0x14)
            }

            success := call(
                gas(),
                tokenB,
                0x00,
                freePtr,
                0x24,
                add(freePtr, 0x44),
                0x20
            )

            //tokenA balance: freePtr + 0x24..0x44
            //tokenB balance: freePtr + 0x44...0x64

            //now we need to derive proportional fee amounts:
            //(lpAmount / totalLP) * tokenA/tokenB

            let tokenAQuantity := div(
                mul(
                    lpAmount,
                    mload(add(freePtr, 0x24))
                ),
                lpTokenTotalSupply
            )

            let tokenBQuantity := div(
                mul(
                    lpAmount,
                    mload(add(freePtr, 0x44))
                ),
                lpTokenTotalSupply
            )

            //Only transfer if there are tokens to transfer
            if xor(add(tokenAQuantity, tokenBQuantity), 0x00)
            {
                //transfer to user -- we set this up now because we know we will need it
                mstore(freePtr, 0xa9059cbb00000000000000000000000000000000000000000000000000000000)
                mstore(add(freePtr, 0x04), caller())

                //could be zero
                if xor(tokenAQuantity, 0x00)
                {
                    mstore(add(freePtr, 0x24), tokenAQuantity)

                    success := call(
                        gas(),
                        tokenA,
                        0x00,
                        freePtr,
                        0x44,
                        0x00,
                        0x00
                    )

                    if iszero(success)
                    {
                        //failed to transfer
                        mstore(0x0, 0x5472616e73666572206661696c65640000000000000000000000000000000000)
                        revert(0x0, 0x0F)
                    }
                }

                //could be zero
                if xor(tokenBQuantity, 0x00)
                {
                    mstore(add(freePtr, 0x24), tokenBQuantity)

                    success := call(
                        gas(),
                        tokenB,
                        0x00,
                        freePtr,
                        0x44,
                        0x00,
                        0x00
                    )

                    if iszero(success)
                    {
                        //failed to transfer
                        mstore(0x0, 0x5472616e73666572206661696c65640000000000000000000000000000000000)
                        revert(0x0, 0x0F)
                    }
                }

            }

            amountA := div(
                mul(lpAmount, sload(tokenAQuantityInReserve.slot)),
                lpTokenTotalSupply
            )

            amountB := div(
                mul(lpAmount, sload(tokenBQuantityInReserve.slot)),
                lpTokenTotalSupply
            )

            //burn LP tokens -- burn(msg.sender, lpAmount)
            freePtr := mload(0x40)
            mstore(freePtr, 0x9dc29fac00000000000000000000000000000000000000000000000000000000)
            mstore(add(freePtr, 0x04), caller())
            mstore(add(freePtr, 0x24), lpAmount)

            success := call(
                gas(),
                sload(lpToken.slot),
                0x00,
                freePtr,
                0x44,
                0x00,
                0x00
            )

            if iszero(success)
            {
                mstore(0x0, 0x4661696c656420746f206275726e2100000000000000000000000000000000)
                revert(0x0, 0x0F)
            }

            //transfer pooled tokens to user (pooledToken.transfer(msg.sender, amountA))
            mstore(freePtr,  0xa9059cbb00000000000000000000000000000000000000000000000000000000)
            mstore(add(freePtr, 0x04), caller())
            mstore(add(freePtr, 0x24), amountA)

            success := call(
                gas(),
                sload(tokenA),
                0x00,
                freePtr,
                0x44,
                0x00,
                0x00
            )

            if iszero(success)
            {
                //Failed to transfer token A!
                mstore(0x0, 0x4661696c656420746f207472616e7366657220746f6b656e2041210000000000)
                revert(0x0, 0x1B)
            }

            mstore(add(freePtr, 0x24), amountB)
            success := call(
                gas(),
                sload(tokenB),
                0x00,
                freePtr,
                0x44,
                0x00,
                0x00
            )

            if iszero(success)
            {
                //Failed to transfer token B!
                mstore(0x0, 0x4661696c656420746f207472616e7366657220746f6b656e2042210000000000)
                revert(0x0, 0x1B)
            }

        }

        _update_reserves(pooledA - amountA, pooledB - amountB);
    }

    //We only use one swap function to reduce bytecode, as the gas cost increase 
    //Is largely negligible compared to the swapAForB / swapBForA approach.
    function swap(uint256 amountIn, address tokenIn)
    external ReentrancyGuard
    {
        bool swappingAForB = true;
        uint256 amountInWithFee;
        uint256 amountBOut;

        /// @solidity memory-safe-assembly
        assembly
        {
            //At this point, we may be wrong about which is tokenIn / tokenOut
            //But we can grab them now and update without another sstore becuase
            //we know "tokenIn" will hold the correct tokenInAddress if it passes
            //the next test.
            let tokenInAddress := sload(pooledTokenA.slot)
            let tokenOutAddress := sload(pooledTokenB.slot)

            if iszero(
                or(
                    eq(tokenInAddress, tokenIn),
                    eq(tokenOutAddress, tokenIn)
                )
            )
            {
                //Invalid token address!
                mstore(0x0, 0x496e76616c696420746f6b656e206164647265737321000000000000000000)
                revert(0x0, 0x16)
            }

            let reserveIn
            let reserveOut

            // Now we need to make sure in/out are accurate
            // In this case, tokenIn is actually tokenB
            if xor(tokenInAddress, tokenIn)
            {
                tokenOutAddress := tokenInAddress
                tokenInAddress := tokenIn

                reserveIn := sload(tokenBQuantityInReserve.slot)
                reserveOut := sload(tokenAQuantityInReserve.slot)
                swappingAForB := 0
            }

            //Otherwise, tokenA is tokenIn
            if swappingAForB
            {
                reserveIn := sload(tokenAQuantityInReserve.slot)
                reserveOut := sload(tokenBQuantityInReserve.slot)
            }

            //Can't swap zero tokens!
            if iszero(amountIn)
            {
                mstore(0x0, 0x43616e27742073776170207a65726f20746f6b656e73210000000000000000)
                revert(0x0, 0x17)
            }

            //transfer from caller to this
            let freePtr := mload(0x40)
            mstore(freePtr, 0x23b872dd00000000000000000000000000000000000000000000000000000000)
            mstore(add(freePtr, 0x04), caller())
            mstore(add(freePtr, 0x24), address())
            mstore(add(freePtr, 0x44), amountIn)

            let success := call(
                gas(),
                tokenInAddress,
                0,
                freePtr,
                0x64,
                0x00,
                0x00
            )

            if iszero(success)
            {
                //Failed to transfer tokenIn!
                mstore(0x0, 0x4661696c656420746f207472616e7366657220746f6b656e496e2100000000)
                revert(0x0, 0x1B)
            }

            let txFee := div(
                mul(
                    sload(fee.slot),
                    amountIn
                ),
                1000
            )

            amountInWithFee := sub(amountIn, txFee)

            //We solve for amountBOut: (reserveA + amountAIn) * (reserveB - amountBOut) = x * y === k
            // (reserveB * amountAIn) / (reserveA + amountAIn) = amountBOut
            // CPMM model (uni v2)
            amountBOut := div(
                mul(
                    reserveOut,
                    amountInWithFee
                ),
                add(
                    reserveIn,
                    amountInWithFee
                )
            )

            //send to user
            mstore(freePtr, 0xa9059cbb00000000000000000000000000000000000000000000000000000000)
            mstore(add(freePtr, 0x04), caller())
            mstore(add(freePtr, 0x24), amountBOut)

            success := call(
                gas(),
                tokenOutAddress,
                0x00,
                freePtr,
                0x44,
                0x00,
                0x00
            )

            if iszero(success)
            {
                //Failed to transfer to sender!
                mstore(0x0, 0x4661696c656420746f207472616e7366657220746f2073656e64657221000000)
                revert(0x0, 0x1D)
            }
        }

        if(swappingAForB)
        {
            _update_reserves(
                tokenAQuantityInReserve + amountInWithFee,
                tokenBQuantityInReserve - amountBOut
            );
        }
        else
        {
            _update_reserves(
                tokenAQuantityInReserve - amountBOut,
                tokenBQuantityInReserve + amountInWithFee
            );
        }

    }

}