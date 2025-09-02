# Xion Mainnet Upgrade Path

## Overview

This document outlines the complete upgrade history of the Xion mainnet blockchain, including all governance proposals, upgrade heights, and recommended versions for each release.

## Current Status

- **Latest Release**: v21.0.0 (Pending deployment)
- **Current Mainnet**: v20.0.0
- **Recommended Version**: v20.0.0

## Complete Upgrade History

### Complete Upgrade Timeline

| Upgrade Name | Height | Proposal | Recommended | Status |
|--------------|---------|-----------|--------|---------|
| [Genesis](v4.md) | 0 | N/A | [v4.0.0](https://github.com/burnt-labs/xion/releases/tag/v4.0.0) | ✅ Complete |
| [v0.3.9](v6.md) | [606,689](https://www.mintscan.io/xion/block/606689) | [#001](../proposals/001-upgrade-v0.3.9.json) | [v6.0.1](https://github.com/burnt-labs/xion/releases/tag/v6.0.1) | ✅ Complete |
| [v7.0.0](v7.md) | [1,637,000](https://www.mintscan.io/xion/block/1637000) | [#002](../proposals/002-upgrade-v7.0.0.json) | [v7.0.1](https://github.com/burnt-labs/xion/releases/tag/v7.0.1) | ✅ Complete |
| [v9](v9.md) | [1,960,000](https://www.mintscan.io/xion/block/1960000) | [#005](../proposals/005-upgrade-v9.json) | [v9.0.2](https://github.com/burnt-labs/xion/releases/tag/v9.0.2) | ✅ Complete |
| [v11](v11.md) | [3,150,000](https://www.mintscan.io/xion/block/3150000) | [#007](../proposals/007-upgrade-v11.json) | [v11.0.1](https://github.com/burnt-labs/xion/releases/tag/v11.0.1) | ✅ Complete |
| [v14](v14.md) | [3,586,500](https://www.mintscan.io/xion/block/3586500) | [#011](../proposals/011-upgrade-v14.json) | [v14.1.2](https://github.com/burnt-labs/xion/releases/tag/v14.1.2) | ✅ Complete |
| [v16](v16.md) | [5,825,000](https://www.mintscan.io/xion/block/5825000) | [#023](../proposals/023-upgrade-v16.json) | [v16.0.1](https://github.com/burnt-labs/xion/releases/tag/v16.0.1) | ✅ Complete |
| [v17](v17.md) | [5,942,000](https://www.mintscan.io/xion/block/5942000) | [#025](../proposals/025-upgrade-v17.json) | [v17.1.1](https://github.com/burnt-labs/xion/releases/tag/v17.1.1) | ✅ Complete |
| [v18](v18.md) | [7,020,000](https://www.mintscan.io/xion/block/7020000) | [#034](../proposals/034-upgrade-v18.json) | [v18.0.2](https://github.com/burnt-labs/xion/releases/tag/v18.0.2) | ✅ Complete |
| [v19](v19.md) | [9,150,000](https://www.mintscan.io/xion/block/9150000) | [#040](../proposals/040-upgrade-v19.json) | [v19.0.2](https://github.com/burnt-labs/xion/releases/tag/v19.0.2) | ✅ Complete |
| [v20](v20.md) | [10,930,000](https://www.mintscan.io/xion/block/10930000) | [#044](../proposals/044-upgrade-v20.json) | [v20.0.0](https://github.com/burnt-labs/xion/releases/tag/v20.0.0) | ✅ Complete |
| [v21](v21.md) | [12,690,000](https://www.mintscan.io/xion/block/12690000) | [#047](../proposals/047-upgrade-v21.json) | [v21.0.0](https://github.com/burnt-labs/xion/releases/tag/v21.0.0) | 🟡 Pending |

## Version Recommendations

### ✅ Recommended Versions

- **v6.0.1**: Latest stable for v6 series
- **v7.0.1**: Latest stable for v7 series  
- **v9.0.2**: Latest stable for v9 series
- **v11.0.1**: Latest stable for v11 series (⚠️ v11.0.0 is deprecated)
- **v14.1.2**: Latest stable for v14 series
- **v16.0.1**: Latest stable for v16 series
- **v17.1.1**: Latest stable for v17 series
- **v18.0.2**: Latest stable for v18 series
- **v19.0.2**: Latest stable for v19 series (⚠️ v19.0.0 is deprecated)
- **v20.0.0**: Current mainnet version

### ⚠️ Deprecated Versions

- **v11.0.0**: Known issues, use v11.0.1 instead
- **v19.0.0**: Known issues, use v19.0.2 instead

## Upgrade Process

### For Validators

1. Monitor governance proposals for upcoming upgrades
2. Download and verify the upgrade binary before the upgrade height
3. Stop the node at the specified upgrade height
4. Replace the binary with the new version
5. Restart the node to continue with the upgraded software

### For Node Operators

1. Follow the same process as validators
2. Ensure backup of node data before upgrades
3. Test upgrades on testnet before mainnet deployment

## Important Notes

- **Skip Versions**: Some version numbers (v4, v5, v8, v10, v12, v13, v15) changes were deployed as part of subsequent major releases
- **Binary Compatibility**: Each upgrade requires updating to the specific binary version - older versions will not work after the upgrade height
- **Governance**: All upgrades are coordinated through on-chain governance proposals that must pass before implementation

## Release Channels

- **GitHub Releases**: [burnt-labs/xion releases](https://github.com/burnt-labs/xion/releases)
- **Docker Images**: Available for each release version
- **Source Code**: Full source available on GitHub for building from source

## Support

For upgrade support and questions:

- GitHub Issues: [burnt-labs/xion/issues](https://github.com/burnt-labs/xion/issues)
- Documentation: Check individual release notes for detailed upgrade instructions
- Community: Xion Discord and Telegram channels

---

*This document is updated with each new release. Last updated: Current as of v21.0.0 release.*
