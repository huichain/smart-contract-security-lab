// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title SimpleProxy
/// @notice Minimal upgradeable proxy for security education.
/// @dev Users call this contract; logic runs from `implementation` via `delegatecall`,
///      so state changes are stored in the proxy's storage slots.
///      The implementation pointer lives in the EIP-1967 slot so it does not collide
///      with the logic contract's slot-0 variables (e.g. `owner`).
contract SimpleProxy {
    event Upgraded(address indexed previousImplementation, address indexed newImplementation);

    constructor(address implementation_) {
        require(implementation_ != address(0), "zero implementation");

        _setImplementation(implementation_);
    }

    function implementation() external view returns (address impl) {
        return _getImplementation();
    }

    /// @notice Points the proxy at a new implementation contract.
    /// @dev Intentionally has no access control in this teaching proxy — upgrade
    ///      permission risks are covered in later steps of this lab module.
    function upgradeTo(address newImplementation) external {
        require(newImplementation != address(0), "zero implementation");

        address previousImplementation = _getImplementation();
        _setImplementation(newImplementation);

        emit Upgraded(previousImplementation, newImplementation);
    }

    fallback() external payable {
        _delegate(_getImplementation());
    }

    receive() external payable {}

    /// @dev EIP-1967: keep the implementation pointer out of the logic contract's slot-0..n range.
    function _implementationSlot() private pure returns (bytes32 slot) {
        return bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
    }

    function _getImplementation() internal view returns (address impl) {
        bytes32 slot = _implementationSlot();
        assembly {
            impl := sload(slot)
        }
    }

    function _setImplementation(address newImplementation) internal {
        bytes32 slot = _implementationSlot();
        assembly {
            sstore(slot, newImplementation)
        }
    }

    function _delegate(address impl) internal {
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }
}
