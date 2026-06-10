// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ImplementationV1
/// @notice Logic contract for a toy upgradeable vault.
/// @dev This version deliberately omits initializer protection. When used behind
///      `SimpleProxy`, anyone can call `initialize()` and seize `owner`.
contract ImplementationV1 {
    address public owner;
    uint256 public value;

    event Initialized(address indexed owner);
    event ValueChanged(uint256 oldValue, uint256 newValue);

    /// @notice Sets the owner of the proxy storage.
    /// @dev Vulnerability: no access control and no one-time guard.
    ///      - Any account can call this function.
    ///      - It can be called again to overwrite the current owner.
    function initialize(address owner_) external {
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
