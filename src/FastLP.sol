//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import '../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol';

contract FastLP is ERC20
{
    address private _owner;

    uint256 constant OPERATOR_SEED_SLOT = 0x1e1e1e;

    modifier OnlyOperator
    {
        //verify that sender is allowed to mint / burn
        require(_get_is_user_an_operator(msg.sender));
        _;
    }

    constructor() ERC20("FastLP", "FP")
    {
        _owner = msg.sender;
        _mint(msg.sender, 1_000e18);
        _add_new_user_as_operator(msg.sender);
    }

    function mint(address user, uint256 amount)
    external OnlyOperator
    {
        _mint(user, amount);
    }

    function burn(address user, uint256 amount)
    external OnlyOperator
    {
        _burn(user, amount);
    }

    function add_new_user_as_operator(address user)
    external
    {
        require(msg.sender == _owner);

        _add_new_user_as_operator(user);
    }

    function _add_new_user_as_operator(address user)
    internal
    {   
        /// @solidity memory-safe-assembly
        assembly
        {
            mstore(0x0, or(
                    shl(232, OPERATOR_SEED_SLOT),
                    shl(72, user)
                )
            )
            sstore(keccak256(0x0, 0xB8), 0x1)
        }
    }

    function _get_is_user_an_operator(address user)
    internal view
    returns(bool)
    {
        bool isOperator = false;
        
        /// @solidity memory-safe-assembly
        assembly
        {
            mstore(0x0, or(
                    shl(232, OPERATOR_SEED_SLOT),
                    shl(72, user)
                )
            )
            isOperator := sload(keccak256(0x0, 0xB8))
        }

        return isOperator;
    }

}