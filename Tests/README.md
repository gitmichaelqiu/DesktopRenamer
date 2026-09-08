# SpaceAPI contract tests

The project does not currently contain an Xcode test target. The Foundation-only
contract harness can be compiled and run from the repository root with:

```sh
swiftc -swift-version 5 \
    DesktopRenamer/Services/API/Contract/Definitions.swift \
    DesktopRenamer/Services/API/Contract/JSONTypes.swift \
    DesktopRenamer/Services/API/Contract/Validation.swift \
    DesktopRenamer/Services/API/Contract/Codec.swift \
    DesktopRenamer/Services/API/SpaceAPI/LegacyFormat.swift \
    Tests/SpaceAPIContractTests.swift \
    -o /tmp/DesktopRenamerSpaceAPIContractTests
/tmp/DesktopRenamerSpaceAPIContractTests
```
