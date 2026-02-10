# dcTools Codebase Analysis

## Executive Summary

**dcTools** is a collection of Node.js automation scripts designed to streamline Perforce (P4) version control operations for a game development project (appears to be "DC World Champions" or similar based on stream naming conventions). The toolkit automates file merging, stream integration, changelist management, and LiveOps asset copying across multiple Perforce workspaces.

---

## 1. Project Structure and Organization

```
dcTools/
├── .git/                           # Git repository data
├── .gitignore                      # Standard Node.js gitignore template
├── IMPLEMENTATION_SUMMARY.md       # Documentation for changelist validator
├── USAGE_EXAMPLE.js                # Usage guide for changelist validator
├── changelistValidator.js          # Utility module for CL validation
├── changelists.txt                 # Input file for changelist numbers
├── liveopsEvents.json              # Configuration for LiveOps asset copying
│
├── # Core Merge Scripts (Changelist-based)
├── mergeByChangelists.js           # Merge files based on changelist numbers
├── mergeByFilePaths.js             # Merge specific file paths
├── getFilePathByChangelist.js      # Extract file paths from changelists
│
├── # Stream Integration Scripts (Downstream - Merge Down)
├── mergeClientStreams.js           # Client/Assets stream integration
├── mergeCombatLuaStreams.js        # Combat Lua stream integration
├── mergeConfigStreams.js           # Config stream integration
│
├── # Stream Integration Scripts (Upstream - Merge Up)
├── mergeUpClientStreams.js         # Client/Assets upstream merge
├── mergeUpCombatLuaStreams.js      # Combat Lua upstream merge
├── mergeUpConfigStreams.js         # Config upstream merge
│
├── finalCheck.js                   # Final verification/integration script
└── copyLiveOpsEvents.js            # LiveOps asset copying automation
```

---

## 2. Main Technologies and Frameworks

| Technology | Purpose | Version/Details |
|------------|---------|-----------------|
| **Node.js** | Runtime environment | Standard Node.js |
| **Perforce (P4)** | Version control system | CLI commands via `child_process` |
| **JavaScript (ES6+)** | Primary language | Async/await, arrow functions, destructuring |

### Core Node.js Modules Used
- `fs` - File system operations
- `path` - Path manipulation
- `child_process` (execSync) - P4 command execution

### No External Dependencies
The project uses **only native Node.js modules** - no `package.json` or `node_modules` required.

---

## 3. Key Directories and Their Purposes

### Perforce Workspaces (External Dependencies)

The scripts interact with multiple Perforce workspaces organized by content type:

| Workspace Type | Windows Path | Mac Path | Purpose |
|----------------|--------------|----------|---------|
| **Company_Windows** | `C:/Users/hoang/Perforce/Company_Windows` | `/Users/hoangnguyen/Perforce/Company_MacbookPro` | Main client source |
| **Company_Windows_Config** | Same pattern | Same pattern | Configuration files source |
| **Company_Windows_Combat_Lua** | Same pattern | Same pattern | Combat Lua scripts source |
| **Desktop_Merge_Target_Client** | Same pattern | `MacbookPro_Merge_Target_Client` | Client merge target |
| **Desktop_Merge_Target_Config** | Same pattern | Same pattern | Config merge target |
| **Desktop_Merge_Target_Combat_Lua** | Same pattern | Same pattern | Combat Lua merge target |

### Stream Structure

The project uses a **hierarchical stream model**:
```
Patch Streams (v1_1_14_12_Patch_A_*)
    ↓ merge down
Parent Streams (v1_1_14_Parent_*)
    ↓ merge down
Trunk Streams (trunk, config, combat_lua)
    ↓ merge down
Staging Streams (Gear_Character_Staging_*)
```

---

## 4. Important Files and Configuration

### Input Files

| File | Purpose | Format |
|------|---------|--------|
| `changelists.txt` | List of P4 changelist numbers to process | One CL number per line |
| `liveopsEvents.json` | LiveOps event configuration | JSON with character, reinforcement, artifact data |

### Example `liveopsEvents.json` Structure:
```json
{
  "character": {
    "epic": [],
    "legendary": [{"id": "13132", "name": "Joker"}]
  },
  "reinforcement": [],
  "artifact": []
}
```

### Core Modules

| File | Exports | Description |
|------|---------|-------------|
| `changelistValidator.js` | 7 functions | Validates CLs, detects review CLs, resolves actual CLs |

**Exported Functions:**
- `isValidChangelist(clNumber, workspace)` - Check if CL exists
- `isReviewChangelist(clNumber, workspace)` - Detect review/pending CLs
- `getActualChangelistFromReview(reviewCl, workspace)` - Find submitted CL from review
- `findReferencedChangelistInDescription(reviewCl, workspace)` - Parse CL refs from description
- `validateAndResolveChangelist(clNumber, workspace)` - Process single CL
- `validateChangelistArray(clArray, workspace)` - Batch process CLs
- `runP4Command(cmd, cwd)` - Execute P4 commands

---

## 5. Architecture Patterns and Design

### Console Logging Enhancement
All scripts use a consistent colored console output pattern:

```javascript
const colors = {
    reset: "\x1b[0m",
    yellow: "\x1b[33m",    // Warnings
    red: "\x1b[31m",       // Errors
    cyan: "\x1b[36m"       // Info
};

console.warn = (...args) => {
    originalWarn(colors.yellow + "[WARNING]", ...args, colors.reset);
};
```

### Cross-Platform Configuration
All scripts support both Windows and macOS:

```javascript
const WORKSPACE_PATH = process.platform === 'win32' 
    ? 'C:/Users/hoang/Perforce/Desktop_Merge_Target_Client' 
    : '/Users/hoangnguyen/Perforce/MacbookPro_Merge_Target_Client';
```

### P4 Command Execution Pattern
```javascript
function runP4Command(command, cwd) {
    try {
        const output = execSync(command, { 
            cwd: cwd, 
            encoding: 'utf8',
            maxBuffer: 1024 * 1024 * 100  // 100MB buffer
        });
        return output.trim();
    } catch (error) {
        console.error(`[ERROR] Failed to run command: ${command} at ${cwd}`);
        return null;
    }
}
```

### File Processing Workflow
1. **Sync** - Update workspaces to latest (`p4 sync //...`)
2. **Read Input** - Parse changelists.txt or liveopsEvents.json
3. **Validate** - Check CLs for validity, detect review CLs
4. **Create CL** - Create new changelist in target workspace
5. **Process Files** - Copy/delete files based on action type
6. **Reconcile** - Add/edit files to P4 (`p4 reconcile`)

### Stream Integration Workflow
1. **Switch Stream** - `p4 client -s -S <stream>`
2. **Sync** - `p4 sync`
3. **Create CL** - Create changelist for merge
4. **Integrate** - `p4 integrate -i` between streams
5. **Resolve** - `p4 resolve -am -dw` (auto-merge, ignore whitespace)

---

## 6. Dependencies and External Integrations

### Perforce Server Integration

**Required P4 Commands Used:**
| Command | Purpose |
|---------|---------|
| `p4 sync` | Update workspace to latest |
| `p4 describe -s <CL>` | Get changelist details |
| `p4 changes -m <N>` | List recent changelists |
| `p4 where "<path>"` | Map depot path to local path |
| `p4 change -o | p4 change -i` | Create new changelist |
| `p4 edit -c <CL> "<file>"` | Open file for edit |
| `p4 delete -c <CL> "<file>"` | Mark file for delete |
| `p4 reconcile -c <CL> -a -e` | Reconcile add/edit |
| `p4 integrate -c <CL> -i` | Integrate between streams |
| `p4 resolve -c <CL> -am -dw` | Auto-resolve conflicts |
| `p4 client -s -S <stream>` | Switch workspace stream |

### Environment Requirements
- **Perforce client (`p4`)** must be in PATH
- **.p4config** files expected in workspace roots
- **Proper P4 authentication** (P4TICKETS or login)

---

## 7. Build and Deployment Setup

### No Build Process Required
- Pure JavaScript - no transpilation needed
- No package manager dependencies
- Run directly with `node <script>.js`

### Execution Examples
```bash
# Merge files based on changelists.txt
node mergeByChangelists.js

# Integrate streams (downstream)
node mergeClientStreams.js
node mergeCombatLuaStreams.js
node mergeConfigStreams.js

# Integrate streams (upstream)
node mergeUpClientStreams.js
node mergeUpCombatLuaStreams.js
node mergeUpConfigStreams.js

# Copy LiveOps assets
node copyLiveOpsEvents.js

# Final verification
node finalCheck.js
```

### Prerequisites
1. Node.js installed
2. Perforce client installed and configured
3. Access to all configured workspaces
4. Proper P4 authentication

---

## 8. Notable Patterns and Conventions

### Naming Conventions
- **camelCase** for variables and functions
- **SCREAMING_SNAKE_CASE** for constants
- Descriptive function names (`syncSourceToLatest`, `createTargetChangelist`)

### Error Handling
- Try-catch around P4 commands
- Null returns on failure (not exceptions)
- Colored console output for visibility
- Graceful degradation (continue on non-critical errors)

### Code Structure
Each script follows a consistent pattern:
1. **Console color setup** (top)
2. **Configuration constants** (workspaces, streams, descriptions)
3. **Helper functions** (P4 commands, file operations)
4. **Main logic** (async function with sequential steps)
5. **Script execution** (call to main())

### File Action Handling
```javascript
const action = fileObj.action;
if (action === 'delete') {
    // Handle deletion
} else if (['add', 'edit'].includes(action)) {
    // Handle add/edit
}
```

### Read-Only File Handling
Windows P4 marks files as read-only. Scripts handle this:
```javascript
fs.chmodSync(targetLocalPath, 0o666); // Remove read-only before overwrite
```

---

## 9. Recent Commits and Project Status

### Git Repository
- **Remote:** https://github.com/nhhoang/dcTools.git
- **Main branch:** `main`
- **Other branches:** `win`, `mac`

### Commit History (Most Recent First)
| Date | Hash | Message |
|------|------|---------|
| 2026-02-09 | 92a6048 | fix space in file nam |
| 2026-01-26 | 64666ba | update files |
| 2026-01-22 | eb1da2a | aloo |
| 2026-01-20 | 20e63d8 | fix |
| 2026-01-20 | ec475be | fix |
| 2026-01-15 | 76e74b7 | test |
| 2026-01-15 | b1b035a | update code |
| 2026-01-15 | f257db7 | update path |
| 2026-01-14 | ce4e424 | add files |
| 2026-01-14 | 2ddea64 | Initial commit |

### Project Maturity
- **Status:** Active development
- **Age:** ~1 month (since Jan 14, 2026)
- **Last update:** Feb 9, 2026
- **Recent focus:** Bug fixes, changelist validation implementation

---

## 10. Script Reference

### mergeByChangelists.js
**Purpose:** Merge files from source to target workspace based on changelist numbers.
**Input:** `changelists.txt`
**Flow:** Read CLs -> Validate -> Get files from each CL -> Copy to target -> Reconcile

### mergeByFilePaths.js
**Purpose:** Merge specific hardcoded file paths.
**Input:** Hardcoded `FILE_PATHS` array
**Use case:** When specific files need merging (not entire CLs)

### getFilePathByChangelist.js
**Purpose:** Extract and display file paths from changelists (investigation tool).
**Input:** `changelists.txt`

### mergeClientStreams.js / mergeCombatLuaStreams.js / mergeConfigStreams.js
**Purpose:** Downstream integration (Patch -> Parent -> Trunk -> Staging)
**Flow:** Switch stream -> Sync -> Create CL -> Integrate -> Resolve

### mergeUpClientStreams.js / mergeUpCombatLuaStreams.js / mergeUpConfigStreams.js
**Purpose:** Upstream integration (Staging -> Trunk -> Patch)
**Flow:** Same as downstream but reversed direction

### finalCheck.js
**Purpose:** Final verification between specific stream versions
**Use case:** Cross-version verification before release

### copyLiveOpsEvents.js
**Purpose:** Copy LiveOps-related assets based on JSON configuration
**Input:** `liveopsEvents.json`
**Assets:** Textures, prefabs, icons for characters/reinforcements/artifacts

### changelistValidator.js
**Purpose:** Utility module for changelist validation
**Exported:** 7 functions for CL validation and resolution

---

## 11. Quick Start Guide

### Prerequisites
1. Install Node.js
2. Install Perforce client (`p4`)
3. Configure P4 credentials
4. Set up required workspaces on your machine

### Basic Usage

1. **Edit changelists.txt** with CL numbers to merge:
   ```
   344885
   344886
   344887
   ```

2. **Run the merge script:**
   ```bash
   node mergeByChangelists.js
   ```

3. **Review in P4V** before submitting

### For Stream Integration

1. **Edit stream constants** in the appropriate script
2. **Run the script:**
   ```bash
   node mergeClientStreams.js
   ```

### For LiveOps Assets

1. **Edit liveopsEvents.json:**
   ```json
   {
     "character": {
       "legendary": [{"id": "13132", "name": "Joker"}]
     }
   }
   ```

2. **Run:**
   ```bash
   node copyLiveOpsEvents.js
   ```

---

## 12. Potential Improvements

1. **Add package.json** for better project management
2. **Implement configuration file** (replace hardcoded paths)
3. **Add unit tests** for validation logic
4. **Create CLI interface** with argument parsing
5. **Add dry-run mode** for preview without changes
6. **Implement logging to file** for audit trail
7. **Add parallel processing** for large file sets
8. **Create unified entry point** (e.g., `dctools.js` with subcommands)

---

*Generated: February 10, 2026*
*Analysis based on codebase at: C:\Users\hoang\Perforce\dcTools*
