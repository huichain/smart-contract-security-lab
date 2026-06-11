// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/// @title FixedImplementationV1
/// @notice Same external interface as `ImplementationV1`, but `initialize` is protected.
/// @dev Fix applied:
///      1. `initializer` modifier — initialization can succeed only once per proxy.
///      2. `_disableInitializers()` in the constructor — the logic contract itself
///         cannot be initialized directly, only the proxy address may be initialized.
contract FixedImplementationV1 is Initializable {
    address public owner;
    uint256 public value;

    event Initialized(address indexed owner);
    event ValueChanged(uint256 oldValue, uint256 newValue);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice One-time initializer for proxy storage.
    function initialize(address owner_) external initializer {
        require(owner_ != address(0), "zero owner");

        owner = owner_;
        emit Initialized(owner_);
    }

    /// @notice Updates the stored value. Only the current owner may call this.
    function setValue(uint256 newValue) external {
        require(msg.sender == owner, "not owner");

        uint256 oldValue = value;
        value = newValue;

        emit ValueChanged(oldValue, newValue);
    }
}
