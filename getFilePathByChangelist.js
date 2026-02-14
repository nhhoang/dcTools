const colors = {
    reset: "\x1b[0m",
    yellow: "\x1b[33m",
    red: "\x1b[31m",
    cyan: "\x1b[36m"
};

// Save original functions
const originalWarn = console.warn;
const originalError = console.error;
const originalLog = console.log;

console.warn = (...args) => {
    originalWarn(colors.yellow + "[WARNING]", ...args, colors.reset);
};

console.error = (...args) => {
    originalError(colors.red + "[ERROR]", ...args, colors.reset);
};

console.log = (...args) => {
    originalLog(colors.cyan, ...args, colors.reset);
};

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const { validateChangelistArray } = require('./changelistValidator');

// ================= CONFIGURATION =================
const CHANGE_LIST_FILE = path.resolve(__dirname, 'changelists.txt');

// Source Workspaces
const CONFIG_SOURCE_WORKSPACE = process.platform === 'win32' 
    ? 'C:/Users/hoang/Perforce/Company_Windows_Config' 
    : '/Users/hoangnguyen/Perforce/MacbookPro_Config'; 
const CLIENT_SOURCE_WORKSPACE = process.platform === 'win32' 
    ? 'C:/Users/hoang/Perforce/Company_Windows' 
    : '/Users/hoangnguyen/Perforce/MacbookPro'; 
const COMBAT_LUA_SOURCE_WORKSPACE = process.platform === 'win32' 
    ? 'C:/Users/hoang/Perforce/Company_Windows_Combat_Lua' 
    : '/Users/hoangnguyen/Perforce/MacbookPro_Combat_Lua';

// Target Workspaces
const CLIENT_TARGET_WORKSPACE = process.platform === 'win32' 
    ? 'C:/Users/hoang/Perforce/Desktop_Merge_Target_Client' 
    : '/Users/hoangnguyen/Perforce/MacbookPro_Merge_Target_Client'; 
const COMBAT_LUA_TARGET_WORKSPACE = process.platform === 'win32' 
    ? 'C:/Users/hoang/Perforce/Desktop_Merge_Target_Combat_Lua' 
    : '/Users/hoangnguyen/Perforce/MacbookPro_Merge_Target_Combat_Lua';

const NEW_CL_DESCRIPTION = 'Auto merge files from Source to Target based on CLs';

// ================= HELPER FUNCTIONS =================

function syncSourceToLatest(workspace) {
    console.log(`--- Syncing Workspace (${workspace}) to the latest revision... ---`);
    const cmd = `p4 sync //...`; 
    const output = runP4Command(cmd, workspace); 
    if (output != null) {
        const syncMessage = output.split('\n').find(line => line.includes('...')) || 'Sync completed successfully.';
        console.log(`[P4 SYNC OK] ${syncMessage}`);
        return true;
    }
    console.error(`[ERROR] Failed to sync workspace: ${workspace}`);
    return false;
}

function runP4Command(command, cwd) {
    try {
        const output = execSync(command, { 
            cwd: cwd, 
            encoding: 'utf8',
            maxBuffer: 1024 * 1024 * 100 
        });
        return output.trim();
    } catch (error) {
        console.error(`[ERROR] Failed to run command: ${command} at ${cwd}`);
        console.error(error.message);
        return null;
    }
}

function getChangelistNumbers(filePath) {
     if (!fs.existsSync(filePath)) {
         console.error(`[ERROR] File not found: ${filePath}`);
         return [];
     }
     const content = fs.readFileSync(filePath, 'utf8');
     const cls = content.split('\n')
         .map(line => line.trim())
         .filter(line => line.length > 0 && !isNaN(line));
     const uniqueCls = [...new Set(cls)];
     
     console.log(`--- Validating ${uniqueCls.length} changelists from file... ---`);
     const { validCls, warnings } = validateChangelistArray(uniqueCls, CONFIG_SOURCE_WORKSPACE);
     
     warnings.forEach(warning => {
         console.warn(warning);
     });
     
     return validCls;
 }

function getChangedFilesFromCLs(clArray) {
    const fileActions = new Map(); 
    console.log(`--- Scanning ${clArray.length} changelists... ---`);

    clArray.forEach(cl => {
        const cmd = `p4 describe -s ${cl}`;
        // Note: Using SOURCE_WORKSPACE as a base to run describe
        const output = runP4Command(cmd, CONFIG_SOURCE_WORKSPACE);
        
        if (output) {
            const lines = output.split('\n');
            lines.forEach(line => {
                line = line.trim();
                if (line.startsWith('... //')) {
                    const match = line.match(/\.\.\.\s+(.+?)#\d+\s+(\S+)$/);
                    if (match) {
                        let depotPath = match[1]; 
                        let action = match[2];
                        
                        if (['add', 'edit', 'delete', 'branch', 'integrate', 'move/add', 'move/delete'].includes(action)) {
                            const isDeleteAction = (action === 'delete' || action === 'move/delete');
                            let finalAction = isDeleteAction ? 'delete' : (action === 'add' || action === 'move/add' ? 'add' : 'edit');
                            console.log(depotPath)
                            // if (!fileActions.has(depotPath)) {
                            //     fileActions.set(depotPath, finalAction);
                            //     console.log(`Found [NEW]: ${finalAction} ${depotPath} in CL:${cl}`);
                            // } else if (isDeleteAction) {
                            //     fileActions.set(depotPath, 'delete');
                            //     console.warn(`Found [DELETE OVERWRITE]: delete ${depotPath} in CL:${cl}`);
                            // }
                        }
                    }
                }
            });
        }
    });
    return Array.from(fileActions, ([depotPath, action]) => ({ depotPath, action }));
}

function convertDepotToLocal(depotPath, workspace) {
    const cmdWhere = `p4 where "${depotPath}"`; 
    const outputWhere = runP4Command(cmdWhere, workspace);
    if (outputWhere) {
        const parts = outputWhere.trim().split(/\s+/);
        if (parts.length >= 3) return parts[2]; 
    }
    return null; 
}

function createTargetChangelist(targetWorkspace) {
    console.log(`--- Creating new Changelist on Target (${targetWorkspace})... ---`);
    const cmd = `p4 --field "Description=${NEW_CL_DESCRIPTION}" change -o | p4 change -i`;
    const output = runP4Command(cmd, targetWorkspace);
    if (output) {
        const match = output.match(/Change (\d+) created/);
        if (match) return match[1];
    }
    return null;
}

// ================= MAIN LOGIC =================

async function main() {
    console.log("=== STARTING MERGE PROCESS ===");

    // 1. Sync all 4 workspaces
    const workspacesToSync = [
        // CONFIG_SOURCE_WORKSPACE, 
        // COMBAT_LUA_SOURCE_WORKSPACE, 
        // CLIENT_TARGET_WORKSPACE, 
        // COMBAT_LUA_TARGET_WORKSPACE
    ];

    for (const ws of workspacesToSync) {
        if (!syncSourceToLatest(ws)) {
            console.error(`[ERROR] Failed to synchronize workspace ${ws}. Aborting.`);
            return;
        }
    }

    // 2. Read CLs
    const cls = getChangelistNumbers(CHANGE_LIST_FILE);
    if (cls.length === 0) {
        console.log("No CLs to process.");
        return;
    }

    // 3. Get file list
    const changedFileObjects = getChangedFilesFromCLs(cls);
    if (changedFileObjects.length === 0) return;

    console.log("=== COMPLETE ===");
    console.log(`Merged ${changedFileObjects.length}.`);
}

main();